import { spawnSync } from 'node:child_process';
import { mkdir, readFile, stat } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const lock = JSON.parse(await readFile(resolve(root, 'tooling/godot.json'), 'utf8'));

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { cwd: root, stdio: 'inherit', ...options });
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} failed with exit code ${result.status}.`);
  return result;
}

try {
  const args = process.argv.slice(2);
  if (args.length > 1 || (args.length === 1 && args[0] !== '--debug')) {
    throw new Error('Usage: node scripts/export-web.mjs [--debug]');
  }
  const godot = process.env.GODOT_BIN || 'godot';
  const version = run(godot, ['--version'], { encoding: 'utf8', stdio: 'pipe' }).stdout.trim();
  if (version !== lock.engineVersion) {
    throw new Error(`Expected ${lock.engineVersion}, received ${version}. Set GODOT_BIN to the pinned editor.`);
  }
  run(process.execPath, [resolve(root, 'scripts/setup-godot.mjs'), '--check']);
  const output = resolve(root, 'build/web/index.html');
  await mkdir(dirname(output), { recursive: true });
  run(godot, ['--headless', '--path', resolve(root, 'game'), '--editor', '--import']);
  run(godot, ['--headless', '--path', resolve(root, 'game'), args[0] === '--debug' ? '--export-debug' : '--export-release', 'Web', output]);
  for (const extension of ['html', 'js', 'wasm', 'pck']) {
    const artifact = resolve(root, `build/web/index.${extension}`);
    if ((await stat(artifact)).size === 0) throw new Error(`Empty export artifact: ${artifact}`);
  }
  console.log(`Web export ready: ${output}`);
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
