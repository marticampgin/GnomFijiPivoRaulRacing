import { createServer } from 'node:http';
import { createReadStream, existsSync, mkdirSync, openSync, writeFileSync } from 'node:fs';
import { stat } from 'node:fs/promises';
import { spawn } from 'node:child_process';
import { dirname, extname, resolve, sep } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = fileURLToPath(import.meta.url);
const root = resolve(dirname(script), '..');
const args = process.argv.slice(2);
if (args.some(arg => !['--serve', '--detach'].includes(arg) && !/^--port=\d+$/.test(arg))) {
  throw new Error('Usage: node scripts/local-web.mjs [--detach] [--port=8788]');
}
const port = Number(args.find(arg => arg.startsWith('--port='))?.split('=')[1] || 8788);
if (port < 1024 || port > 65505) throw new Error('Port must be between 1024 and 65505.');
if (!existsSync(resolve(root, 'build/web/index.html'))) throw new Error('Run scripts/export-web.mjs first.');
const runtime = resolve(root, '.local');
mkdirSync(runtime, { recursive: true });
if (args.includes('--detach')) {
  const log = openSync(resolve(runtime, 'local-web.log'), 'a');
  const child = spawn(process.execPath, [script, '--serve', `--port=${port}`], {
    cwd: root, detached: true, stdio: ['ignore', log, log, 'ipc'],
  });
  const timer = setTimeout(() => { child.kill(); console.error('Static server startup timed out.'); process.exit(1); }, 10000);
  child.once('message', message => {
    clearTimeout(timer); console.log(`Local game: ${message.url} (static assets only; no backend)`);
    child.disconnect(); child.unref();
  });
  child.once('error', error => { clearTimeout(timer); console.error(error); process.exitCode = 1; });
} else {
  const webFiles = new Set(['app.js', 'app.css', 'track-map.js', 'local-race.js', 'local-race.css', 'control-settings.js', 'control-settings.css']);
  const types = { '.html':'text/html; charset=utf-8', '.js':'text/javascript; charset=utf-8', '.css':'text/css; charset=utf-8', '.wasm':'application/wasm', '.png':'image/png', '.jpg':'image/jpeg', '.svg':'image/svg+xml', '.json':'application/json' };
  const server = createServer(async (request, response) => {
    try {
      if (!['GET','HEAD'].includes(request.method)) { response.writeHead(405).end(); return; }
      const pathname = decodeURIComponent(new URL(request.url, 'http://localhost').pathname);
      let base, relative;
      if (pathname === '/') { base = resolve(root, 'build/web'); relative = 'index.html'; }
      else if (webFiles.has(pathname.slice(1))) { base = resolve(root, 'web'); relative = pathname.slice(1); }
      else if (pathname.startsWith('/assets/')) { base = resolve(root, 'web/assets'); relative = pathname.slice(8); }
      else if (/^\/index\.[a-z0-9.]+$/.test(pathname)) { base = resolve(root, 'build/web'); relative = pathname.slice(1); }
      else { response.writeHead(404).end(); return; }
      const path = resolve(base, relative);
      if (!path.startsWith(base + sep)) { response.writeHead(403).end(); return; }
      const info = await stat(path);
      if (!info.isFile()) { response.writeHead(404).end(); return; }
      response.writeHead(200, { 'Content-Type': types[extname(path)] || 'application/octet-stream', 'Content-Length':info.size, 'Cache-Control':'no-store', 'X-Content-Type-Options':'nosniff' });
      if (request.method === 'HEAD') response.end();
      else createReadStream(path).on('error', () => response.destroy()).pipe(response);
    } catch { if (!response.headersSent) response.writeHead(404); response.end(); }
  });
  let selected = port;
  server.on('error', error => {
    if (error.code === 'EADDRINUSE' && selected < port + 30) server.listen(++selected, '127.0.0.1');
    else { console.error(error); process.exitCode = 1; }
  });
  server.once('listening', () => {
    const url = `http://127.0.0.1:${selected}/`;
    writeFileSync(resolve(runtime, `local-web-${selected}.json`), JSON.stringify({pid:process.pid,url}), { mode:0o600 });
    console.log(`Local game: ${url}`);
    process.send?.({url});
  });
  server.listen(selected, '127.0.0.1');
}
