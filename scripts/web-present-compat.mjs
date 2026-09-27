const supportedEngine = '4.7.2.stable.official.ed1daf0bf';
const before = 'blitOffscreenFramebuffer:context=>{var gl=context.GLctx;var prevScissorTest=gl.getParameter(3089);';
const after = before.replace('getParameter(3089)', 'isEnabled(3089)');

// Both APIs return the current SCISSOR_TEST boolean. isEnabled avoids the
// synchronous generic query observed in Chromium's offscreen presentation path.
export function patchWebPresent(source, engineVersion) {
  if (engineVersion !== supportedEngine) {
    throw new Error('Revalidate the Web presentation compatibility patch for this Godot version.');
  }
  const originals = source.split(before).length - 1;
  const patched = source.split(after).length - 1;
  if (originals === 0 && patched === 1) return source;
  if (originals !== 1 || patched !== 0) {
    throw new Error('Unexpected Emscripten presentation source; refusing a partial or ambiguous patch.');
  }
  return source.replace(before, after);
}
