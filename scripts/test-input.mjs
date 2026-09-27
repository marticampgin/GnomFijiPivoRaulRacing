import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const godot = process.env.GODOT_BIN || 'godot';
const lock = JSON.parse(readFileSync(resolve(root, 'tooling/godot.json'), 'utf8'));
const probes = ['local_input', 'control_profile', 'arcade_input', 'ctr_drift'];
const logs = mkdtempSync(join(tmpdir(), 'gnom-input-'));

try {
  if (process.argv.length !== 2) throw new Error('Usage: node scripts/test-input.mjs');
  const version = spawnSync(godot, ['--version'], { encoding: 'utf8', timeout: 10_000 });
  if (version.error) throw version.error;
  if (version.status !== 0 || version.stdout.trim() !== lock.engineVersion) {
    throw new Error(`Expected Godot ${lock.engineVersion}; set GODOT_BIN to the pinned editor.`);
  }
  for (const name of probes) {
    const result = spawnSync(godot, ['--headless', '--path', resolve(root, 'game'),
      '--fixed-fps', '60', '--log-file', join(logs, `${name}.log`),
      '--script', `res://tests/${name}_probe.gd`], { cwd: root, stdio: 'inherit', timeout: 60_000 });
    if (result.error) throw result.error;
    if (result.status !== 0) throw new Error(`${name} probe failed (${result.status}).`);
  }
  console.log('Input and CTR drift probes passed. Physical controller hardware is not verified.');
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
} finally {
  rmSync(logs, { recursive: true, force: true });
}
