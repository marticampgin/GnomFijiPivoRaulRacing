import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import vm from 'node:vm';

const source = await readFile(new URL('../build/web/index.js', import.meta.url), 'utf8');
const begin = source.indexOf('blitOffscreenFramebuffer:');
const end = source.indexOf(',registerContext:', begin);
assert.ok(begin >= 0 && end > begin, 'Expected pinned Emscripten presentation function');
const present = vm.runInNewContext(`(${source.slice(begin + 'blitOffscreenFramebuffer:'.length, end)})`);

for (const enabled of [false, true]) {
  let scissor = enabled;
  const originalFbo = {};
  let framebuffer = originalFbo;
  let draws = 0;
  let scissorQueries = 0;
  let capabilityQueries = 0;
  const gl = {
    canvas: { width: 1600, height: 900 },
    getParameter(parameter) {
      if (parameter === 3089) { scissorQueries++; return scissor; }
      assert.equal(parameter, 36006);
      return framebuffer;
    },
    isEnabled(capability) { assert.equal(capability, 3089); capabilityQueries++; return scissor; },
    enable(capability) { assert.equal(capability, 3089); scissor = true; },
    disable(capability) { assert.equal(capability, 3089); scissor = false; },
    bindFramebuffer(target, value) {
      if (target === 36160 || target === 36009) framebuffer = value;
    },
    blitFramebuffer(...args) {
      assert.equal(scissor, false, 'Present must not be clipped by the scene scissor');
      assert.equal(framebuffer, null);
      assert.deepEqual(args, [0, 0, 1600, 900, 0, 0, 1600, 900, 16384, 9728]);
      draws++;
    },
  };
  for (let frame = 0; frame < 3; frame++) {
    const expectedScissor = frame % 2 === 0 ? enabled : !enabled;
    scissor = expectedScissor;
    present({ GLctx: gl, defaultFbo: {} });
    assert.equal(scissor, expectedScissor, 'Present must restore current scissor state');
    assert.equal(framebuffer, originalFbo, 'Present must restore framebuffer binding');
  }
  assert.equal(draws, 3);
  assert.equal(scissorQueries, 0, 'Present must avoid synchronous getParameter(SCISSOR_TEST)');
  assert.equal(capabilityQueries, 3, 'Query the actual capability each frame, never cache it');
}
console.log('WEB_PRESENT_PASS enabled/disabled scissor, unclipped blit, framebuffer restore, live query');
