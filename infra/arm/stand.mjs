import { spawnSync } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { chmod, mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseEnv } from 'node:util';
import { assertLocalDockerEndpoint } from './docker-endpoint.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, '../..');
const local = resolve(here, '.local');
const envPath = resolve(local, 'stand.env');
const composeArgs = ['compose', '--project-name', 'gnom-arm-stand', '--env-file', envPath, '-f', resolve(here, 'compose.yaml')];

function run(command, args, capture = false) {
  const environment = { ...process.env };
  if (command === 'docker' && args[0] === 'compose') {
    for (const key of ['NODE_IMAGE', 'POSTGRES_IMAGE', 'DATABASE_PASSWORD', 'SESSION_SECRET', 'RACE_TICKET_SECRET', 'RACE_CPUS']) delete environment[key];
  }
  const result = spawnSync(command, args, { cwd: root, env: environment, encoding: 'utf8', stdio: capture ? 'pipe' : 'inherit' });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed (${result.status}); no infrastructure was installed automatically`);
  return result.stdout;
}

async function lockImage({ repository, tag }) {
  const auth = await fetch(`https://auth.docker.io/token?service=registry.docker.io&scope=repository:${repository}:pull`, { signal: AbortSignal.timeout(15000) });
  if (!auth.ok) throw new Error(`Docker registry authentication failed: ${auth.status}`);
  const { token } = await auth.json();
  const response = await fetch(`https://registry-1.docker.io/v2/${repository}/manifests/${tag}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json' },
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new Error(`Image ${repository}:${tag} unavailable: ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  const digest = `sha256:${createHash('sha256').update(bytes).digest('hex')}`;
  if (response.headers.get('docker-content-digest') !== digest) throw new Error('Registry digest mismatch');
  const manifest = JSON.parse(bytes.toString('utf8'));
  const platforms = manifest.manifests?.map(item => `${item.platform?.os}/${item.platform?.architecture}`) ?? [];
  if (!platforms.includes('linux/arm64') || !platforms.includes('linux/amd64')) throw new Error('Expected official multi-architecture image');
  return { image: `docker.io/${repository}:${tag}@${digest}`, digest, platforms };
}

async function init() {
  await mkdir(local, { recursive: true, mode: 0o700 });
  await chmod(local, 0o700);
  try {
    await stat(envPath);
    console.log('Existing stand secrets and image locks preserved; no rotation performed.');
    return;
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  const desired = JSON.parse(await readFile(resolve(here, 'images.json'), 'utf8'));
  const node = await lockImage(desired.node);
  const postgres = await lockImage(desired.postgres);
  const values = {
    NODE_IMAGE: node.image,
    POSTGRES_IMAGE: postgres.image,
    DATABASE_PASSWORD: randomBytes(32).toString('hex'),
    SESSION_SECRET: randomBytes(32).toString('hex'),
    RACE_TICKET_SECRET: randomBytes(32).toString('hex'),
    RACE_CPUS: '2.0',
  };
  await writeFile(resolve(local, 'image-lock.json'), JSON.stringify({ resolvedAt: new Date().toISOString(), node, postgres }, null, 2) + '\n', { mode: 0o600 });
  await writeFile(envPath, Object.entries(values).map(([key, value]) => `${key}=${value}`).join('\n') + '\n', { mode: 0o600, flag: 'wx' });
  console.log('Private stand configuration created. Secrets were not printed. No server or container started.');
}

function checkDockerEndpoint() {
  const context = JSON.parse(run('docker', ['context', 'inspect'], true))[0];
  assertLocalDockerEndpoint(context);
}

async function check() {
  if (process.platform !== 'linux' || process.arch !== 'arm64') throw new Error('Run the stand on native Linux ARM64, not macOS or QEMU');
  if (process.versions.node.split('.')[0] !== '24') throw new Error('Node.js 24 required for the stand launcher');
  checkDockerEndpoint();
  const info = JSON.parse(run('docker', ['info', '--format', '{{json .}}'], true));
  if (info.OSType !== 'linux' || !['arm64', 'aarch64'].includes(info.Architecture)) throw new Error('Docker daemon must also be native Linux ARM64');
  const environment = parseEnv(await readFile(envPath, 'utf8'));
  if (((await stat(envPath)).mode & 0o077) !== 0) throw new Error('stand.env must not be readable by group/others');
  for (const name of ['NODE_IMAGE', 'POSTGRES_IMAGE']) {
    if (!/^docker\.io\/library\/(node|postgres):[^@]+@sha256:[a-f0-9]{64}$/.test(environment[name] ?? '')) throw new Error(`Unpinned ${name}`);
  }
  for (const name of ['DATABASE_PASSWORD', 'SESSION_SECRET', 'RACE_TICKET_SECRET']) {
    if (!/^[a-f0-9]{64}$/.test(environment[name] ?? '')) throw new Error(`Missing generated ${name}`);
  }
  const binary = await readFile(resolve(root, 'build/server/gnom-racing.arm64'));
  if (binary.toString('hex', 0, 4) !== '7f454c46' || binary[4] !== 2 || binary[5] !== 1 || binary.readUInt16LE(18) !== 183) throw new Error('Worker must be a little-endian ARM64 ELF executable');
  const artifacts = {};
  for (const path of ['build/server/gnom-racing.arm64', 'build/server/gnom-racing.pck', 'build/web/index.html', 'build/web/index.wasm', 'build/web/index.pck']) {
    const bytes = await readFile(resolve(root, path));
    if (!bytes.length) throw new Error(`Empty artifact ${path}`);
    artifacts[path] = createHash('sha256').update(bytes).digest('hex');
  }
  run('docker', [...composeArgs, 'config', '--quiet']);
  await writeFile(resolve(local, 'preflight.json'), JSON.stringify({ checkedAt: new Date().toISOString(), architecture: info.Architecture, engineVersion: info.ServerVersion, cpuCount: info.NCPU, ramBytes: info.MemTotal, artifacts }, null, 2) + '\n', { mode: 0o600 });
  console.log('Preflight passed. Artifact validity is not runtime/capacity proof.');
}

try {
  const command = process.argv[2];
  if (process.argv.length !== 3 || !['init', 'check', 'up', 'down', 'status', 'logs'].includes(command)) throw new Error('Usage: node infra/arm/stand.mjs init|check|up|down|status|logs');
  if (command === 'init') await init();
  else if (command === 'check') await check();
  else if (command === 'up') { await check(); run('docker', [...composeArgs, 'up', '--build', '--detach', '--wait', '--wait-timeout', '120']); }
  else {
    checkDockerEndpoint();
    if (command === 'down') run('docker', [...composeArgs, 'down']);
    else if (command === 'status') run('docker', [...composeArgs, 'ps']);
    else run('docker', [...composeArgs, 'logs', '--tail', '100']);
  }
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
