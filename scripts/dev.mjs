import { spawn, spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { createConnection, createServer } from 'node:net';
import { existsSync, mkdirSync, openSync, readFileSync, renameSync, rmSync, writeFileSync, writeSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(import.meta.url);
const root = resolve(dirname(script), '..');
const runtime = resolve(root, '.local');
const recordPath = resolve(runtime, 'dev.json');
const args = process.argv.slice(2);
if (args.length !== 1 || args.some(arg => !['--detach', '--serve', '--stop'].includes(arg))) throw new Error('Usage: node scripts/dev.mjs --detach | --stop | --serve');
mkdirSync(runtime, { recursive: true });
function record() {
  try { return JSON.parse(readFileSync(recordPath, 'utf8')); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}
function saveRecord(value) {
  const temporary = `${recordPath}.${process.pid}.tmp`;
  writeFileSync(temporary, JSON.stringify(value), { mode: 0o600 });
  renameSync(temporary, recordPath);
}
function isCoordinator(pid) {
  if (!Number.isInteger(pid) || pid < 2) return false;
  const result = spawnSync('ps', ['-p', String(pid), '-o', 'command='], { encoding: 'utf8' });
  return result.status === 0 && result.stdout.includes(script) && result.stdout.includes('--serve');
}
if (args[0] === '--stop') {
  const existing = record();
  if (existing && isCoordinator(existing.pid)) {
    process.kill(existing.pid, 'SIGTERM');
    console.log('Stopping this project\'s local server.');
  } else console.log('No running local server for this project.');
  process.exit(0);
}
if (Number(process.versions.node.split('.')[0]) !== 24) throw new Error('Use Node.js 24 LTS for the pinned backend toolchain.');
const existing = record();
if (existing && isCoordinator(existing.pid)) throw new Error(`Local server already running: ${existing.url}. Stop it with --stop before starting another.`);
if (!existsSync(resolve(root, 'build/web/index.html'))) throw new Error('Build the Web client with scripts/export-web.mjs first.');
if (!existsSync(resolve(root, 'backend/dist/local.mjs'))) throw new Error('Install and build the backend with npm --prefix backend ci and npm --prefix backend run build first.');
const godot = process.env.GODOT_BIN || 'godot';
const expected = JSON.parse(readFileSync(resolve(root, 'tooling/godot.json'), 'utf8')).engineVersion;
const version = spawnSync(godot, ['--version'], { encoding: 'utf8' });
if (version.error || version.status !== 0 || version.stdout.trim() !== expected) throw new Error(`GODOT_BIN must point to ${expected}.`);

if (args[0] === '--detach') {
  rmSync(recordPath, { force: true });
  const log = openSync(resolve(runtime, 'dev.log'), 'a');
  writeSync(log, `\nLocal development startup ${new Date().toISOString()}\n`);
  const child = spawn(process.execPath, [script, '--serve'], { cwd: root, env: process.env, detached: true, stdio: ['ignore', log, log] });
  child.unref();
  for (let attempt = 0; attempt < 180; attempt++) {
    await new Promise(resolve => setTimeout(resolve, 1000));
    const current = record();
    if (current?.ready && current.pid === child.pid) {
      console.log(`Local game ready: ${current.url}\nLogs: ${resolve(runtime, 'dev.log')}\nStop: node scripts/dev.mjs --stop`);
      process.exit(0);
    }
    try { process.kill(child.pid, 0); }
    catch { throw new Error('Server startup failed. Inspect .local/dev.log.'); }
  }
  process.kill(child.pid, 'SIGTERM');
  throw new Error('Server startup timed out. Inspect .local/dev.log.');
}

async function availablePort(first) {
  for (let port = first; port < first + 30; port++) {
    const free = await new Promise(resolve => {
      const probe = createServer();
      probe.once('error', () => resolve(false));
      probe.listen(port, '127.0.0.1', () => probe.close(() => resolve(true)));
    });
    if (free) return port;
  }
  throw new Error(`No free local port near ${first}.`);
}
function workerReady(port) {
  return new Promise(resolve => {
    const socket = createConnection({ host: '127.0.0.1', port });
    const finish = ready => { socket.destroy(); resolve(ready); };
    socket.once('connect', () => finish(true));
    socket.once('error', () => finish(false));
    socket.setTimeout(1000, () => finish(false));
  });
}
const port = await availablePort(8787);
const racePort = await availablePort(9080);
const pgPort = await availablePort(55432);
const url = `http://127.0.0.1:${port}`;
const secret = randomBytes(32).toString('hex');
const env = { ...process.env, RACE_TICKET_SECRET: secret, RACE_PORT: String(racePort), RACE_WEBSOCKET_URL: `ws://127.0.0.1:${racePort}`, PORT: String(port), APP_ORIGIN: url, LOCAL_PG_PORT: String(pgPort), DEPLOYMENT_ENV: 'local' };
const worker = spawn(godot, ['--headless', '--path', resolve(root, 'game'), '--max-fps', '60', '--', '--race-worker'], { cwd: root, env, stdio: 'inherit' });
const api = spawn(process.execPath, ['dist/local.mjs'], { cwd: resolve(root, 'backend'), env, stdio: 'inherit' });
const children = [worker, api];
let stopping = false;
async function stop(code = 0) {
  if (stopping) return;
  stopping = true;
  for (const child of children) if (child.exitCode === null) child.kill('SIGTERM');
  await Promise.race([
    new Promise(resolve => setTimeout(resolve, 8000)),
    Promise.all(children.map(child => child.exitCode !== null ? Promise.resolve() : new Promise(resolve => child.once('exit', resolve)))),
  ]);
  for (const child of children) if (child.exitCode === null) child.kill('SIGKILL');
  if (record()?.pid === process.pid) rmSync(recordPath, { force: true });
  process.exit(code);
}
process.once('SIGINT', () => stop());
process.once('SIGTERM', () => stop());
for (const child of children) {
  child.once('error', error => { console.error(error.message); stop(1); });
  child.once('exit', code => { if (!stopping) { console.error(`Local child exited (${code}).`); stop(1); } });
}
saveRecord({ pid: process.pid, url, port, racePort, pgPort, ready: false });
for (let attempt = 0; attempt < 170; attempt++) {
  if (stopping) break;
  try {
    const health = await fetch(`${url}/api/health`, { signal: AbortSignal.timeout(2000) });
    if (health.ok && await workerReady(racePort)) {
      saveRecord({ pid: process.pid, url, port, racePort, pgPort, ready: true });
      console.log(`Local game ready: ${url}`);
      break;
    }
  } catch { /* Wait for PostgreSQL migrations and the worker's socket. */ }
  if (attempt === 169) { console.error('Local API or race worker startup timed out.'); await stop(1); }
  await new Promise(resolve => setTimeout(resolve, 1000));
}
