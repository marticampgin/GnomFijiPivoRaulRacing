import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { patchWebPresent } from './web-present-compat.mjs';

const lock = JSON.parse(await readFile(new URL('../tooling/godot.json', import.meta.url), 'utf8'));
for (const flavor of ['debug', 'release']) {
  const archive = new URL(`../.tools/godot/4.7.2/web_nothreads_${flavor}.zip`, import.meta.url);
  const source = execFileSync('unzip', ['-p', archive.pathname, 'godot.js'], { encoding: 'utf8', maxBuffer: 4 * 1024 * 1024 });
  const result = patchWebPresent(source, lock.engineVersion);
  assert.notEqual(result, source);
  assert.equal(result.replace('var prevScissorTest=gl.isEnabled(3089);', 'var prevScissorTest=gl.getParameter(3089);'), source);
  assert.equal(patchWebPresent(result, lock.engineVersion), result);
  assert.throws(() => patchWebPresent(source + source, lock.engineVersion), /ambiguous/);
  assert.throws(() => patchWebPresent(source + result, lock.engineVersion), /ambiguous/);
  assert.throws(() => patchWebPresent(source, 'future-version'), /Revalidate/);
}
assert.throws(() => patchWebPresent('changed upstream source', lock.engineVersion), /Unexpected/);
console.log('WEB_PRESENT_COMPAT_PASS pinned debug/release, exact change, idempotence, drift/duplicate/version guards');
