const { chromium } = require('playwright');
const sharp = require('sharp');
const fs = require('node:fs/promises');
const path = require('node:path');
const assert = require('node:assert/strict');

const url = new URL(process.env.GNOM_LOCAL_URL || 'http://127.0.0.1:8788/');
assert.ok(['http:', 'https:'].includes(url.protocol)
  && ['localhost', '127.0.0.1', '[::1]'].includes(url.hostname)
  && !url.username && !url.password, 'GNOM_LOCAL_URL must be a localhost HTTP(S) URL');
const output = path.resolve(process.env.GNOM_LOCAL_OUT || process.env.GNOM_LOCAL_OUTPUT || '/tmp/gnom-local-web');
const quality = process.env.GNOM_LOCAL_QUALITY || 'standard';
assert.ok(['standard', 'low'].includes(quality), 'GNOM_LOCAL_QUALITY must be standard or low');
const sampleSeconds = Number(process.env.GNOM_LOCAL_SAMPLE_SECONDS || 0);
assert.ok(Number.isFinite(sampleSeconds) && sampleSeconds >= 0 && sampleSeconds <= 30,
  'GNOM_LOCAL_SAMPLE_SECONDS must be between 0 and 30');
const headless = process.env.GNOM_LOCAL_HEADLESS === '1';

function installVirtualPads() {
  const pads = Array.from({ length: 3 }, (_, index) => ({
    id: `QA virtual pad ${index}`, index, connected: false, mapping: 'standard',
    axes: [0, 0, 0, 0],
    buttons: Array.from({ length: 17 }, () => ({ value: 0, pressed: false, touched: false })),
    timestamp: 0,
  }));
  Object.defineProperty(navigator, 'getGamepads', {
    value: () => pads.map(pad => pad.connected ? { ...pad, timestamp: performance.now() } : null),
  });
  window.qaSetPadConnected = (index, connected) => {
    pads[index].connected = connected;
    const event = new Event(connected ? 'gamepadconnected' : 'gamepaddisconnected');
    Object.defineProperty(event, 'gamepad', { value: { ...pads[index] } });
    window.dispatchEvent(event);
  };
}

async function checkFrozen(page) {
  await page.waitForFunction(() => GnomHost.state.paused);
  const tick = await page.evaluate(() => GnomHost.state.tick);
  await page.waitForTimeout(200);
  assert.equal(await page.evaluate(() => GnomHost.state.tick), tick, 'Paused simulation advanced');
}

async function resume(page) {
  const before = await page.evaluate(() => GnomHost.state.tick);
  await page.locator('#local-resume').click();
  await page.waitForFunction(tick => !GnomHost.state.paused && GnomHost.state.tick > tick, before);
}

async function checkSectors(page, count, layout) {
  assert.equal(await page.locator('.local-pane').count(), count);
  const sectors = await page.evaluate(() => GnomHost.state.sectors);
  assert.equal(sectors.length, count);
  const bounds = await page.locator('.local-pane').evaluateAll(nodes => nodes.map(node => {
    const rect = node.getBoundingClientRect();
    return { x: rect.x / innerWidth, y: rect.y / innerHeight,
      width: rect.width / innerWidth, height: rect.height / innerHeight };
  }));
  for (let index = 0; index < count; index++) {
    for (const key of ['x', 'y', 'width', 'height']) {
      assert.ok(Math.abs(bounds[index][key] - sectors[index][key]) < 0.002,
        `${count}/${layout} P${index + 1}: HTML and Godot sector ${key} differ`);
    }
  }
  const bitmap = await page.locator('#canvas').screenshot();
  const metadata = await sharp(bitmap).metadata();
  const sectorColors = [];
  for (const sector of sectors) {
    const { data, info } = await sharp(bitmap).extract({
      left: Math.round(sector.x * metadata.width), top: Math.round(sector.y * metadata.height),
      width: Math.floor(sector.width * metadata.width), height: Math.floor(sector.height * metadata.height),
    }).resize(160, 90).removeAlpha().raw().toBuffer({ resolveWithObject: true });
    const colors = new Set();
    for (let index = 0; index < data.length; index += info.channels) {
      colors.add(`${data[index] >> 4},${data[index + 1] >> 4},${data[index + 2] >> 4}`);
    }
    assert.ok(colors.size > 40, `${count}/${layout}: canvas sector is blank`);
    sectorColors.push(colors.size);
  }
  return sectorColors;
}

async function measureBrowserCadence(page) {
  // This measures browser callback cadence and published simulation progress, not GPU frame time.
  const measurement = await page.evaluate(seconds => new Promise(resolve => {
    const intervals = [];
    let invalidReason = null;
    const inspect = () => {
      if (document.visibilityState !== 'visible' || !document.hasFocus()) {
        invalidReason = 'Page lost visibility or window focus during the sample';
      }
      if (GnomHost.state?.mode !== 'local' || GnomHost.state?.paused
        || GnomHost.state?.phase !== 'racing' || GnomHost.state?.seats?.length !== 4) {
        invalidReason = 'Four-player race stopped or paused during the sample';
      }
    };
    const initial = { visibility: document.visibilityState, focused: document.hasFocus() };
    const start = performance.now();
    const firstTick = GnomHost.state.tick;
    let previous = null;
    let frameId;
    const onBlur = () => { invalidReason = 'Window blur occurred during the sample'; };
    const onVisibility = () => { inspect(); };
    window.addEventListener('blur', onBlur);
    document.addEventListener('visibilitychange', onVisibility);
    inspect();
    const frame = timestamp => {
      inspect();
      if (previous !== null) intervals.push(timestamp - previous);
      previous = timestamp;
      frameId = requestAnimationFrame(frame);
    };
    frameId = requestAnimationFrame(frame);
    setTimeout(() => {
      inspect();
      cancelAnimationFrame(frameId);
      window.removeEventListener('blur', onBlur);
      document.removeEventListener('visibilitychange', onVisibility);
      intervals.sort((a, b) => a - b);
      const percentile = fraction => intervals.length
        ? intervals[Math.max(0, Math.ceil(intervals.length * fraction) - 1)] : null;
      const tickDelta = GnomHost.state.tick - firstTick;
      resolve({ valid: !invalidReason && intervals.length > 0 && tickDelta > 0,
        invalidReason: invalidReason || (!intervals.length || tickDelta <= 0 ? 'No callback or simulation progress' : null),
        requestedSeconds: seconds, elapsedMs: performance.now() - start,
        requestAnimationFrame: { samples: intervals.length, p50Ms: percentile(0.50),
          p95Ms: percentile(0.95), p99Ms: percentile(0.99) },
        publishedSimulationTickDelta: tickDelta, initial,
        final: { visibility: document.visibilityState, focused: document.hasFocus() },
        graphics: GnomHost.state.graphics || null,
      });
    }, seconds * 1000);
  }), sampleSeconds);
  await fs.writeFile(path.join(output, 'measurement.json'), JSON.stringify(measurement, null, 2));
  assert.ok(measurement.valid, `Measurement rejected: ${measurement.invalidReason}`);
  return measurement;
}

(async () => {
  await fs.mkdir(output, { recursive: true });
  const browser = await chromium.launch({ headless });
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  const errors = [], api = [], sockets = [], results = [];
  let measurement = null;
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
  page.on('pageerror', error => errors.push(error.message));
  page.on('request', request => {
    if (new URL(request.url()).pathname.startsWith('/api/')) api.push(request.url());
  });
  page.on('websocket', socket => sockets.push(socket.url()));
  await page.addInitScript(installVirtualPads);
  await page.addInitScript(selectedQuality => {
    localStorage.setItem('gnom.graphics.v1', JSON.stringify({ quality: selectedQuality, reducedEffects: false }));
  }, quality);
  try {
    await page.goto(url.href);
    await page.waitForFunction(() => {
      const start = document.querySelector('#local-button');
      return start && !start.disabled;
    }, null, { timeout: 90000 });
    assert.equal(new URL(page.url()).origin, url.origin);
    assert.match(await page.title(), /GNOM FIJI/i, 'Wrong application loaded');
    await page.evaluate(() => { for (let index = 0; index < 3; index++) qaSetPadConnected(index, true); });
    for (const [count, layout] of [[1, 'side-by-side'], [2, 'side-by-side'], [2, 'stacked'],
      [3, 'side-by-side'], [4, 'side-by-side']]) {
      await page.locator('#local-button').click();
      await page.getByLabel('Количество игроков', { exact: true }).selectOption(String(count));
      if (count === 2) await page.getByLabel('Разделение экрана', { exact: true }).selectOption(layout);
      for (let index = 1; index < count; index++) {
        await page.locator('#local-setup').getByLabel(`Контроллер P${index + 1}`, { exact: true })
          .selectOption(String(index - 1));
      }
      await page.locator('#local-start').click();
      await page.waitForFunction(players => GnomHost.state?.mode === 'local'
        && GnomHost.state.phase === 'racing' && GnomHost.state.seats.length === players,
      count, { timeout: 15000 });
      assert.equal(await page.evaluate(() => GnomHost.state.graphics?.quality), quality,
        'Godot graphics quality differs from requested quality');
      await page.keyboard.down('w');
      await page.waitForFunction(() => GnomHost.state.seats[0].speed > 15);
      await page.keyboard.up('w');
      const sectorColors = await checkSectors(page, count, layout);
      await page.screenshot({ path: path.join(output, `${count}-${layout}.png`) });
      if (count === 4 && sampleSeconds > 0) {
        await page.bringToFront();
        measurement = await measureBrowserCadence(page);
      }
      await page.locator('.local-pause-button').click();
      await checkFrozen(page);
      await resume(page);
      const recoveryEpoch = await page.evaluate(() => GnomHost.state.seats[0].epoch);
      await page.locator('.local-pause-button').click();
      await page.locator('#local-pause').getByRole('button', { name: 'На трассу', exact: true }).first().click();
      await page.waitForFunction(epoch => !GnomHost.state.paused
        && GnomHost.state.seats[0].epoch > epoch, recoveryEpoch);
      if (count > 1) {
        await page.evaluate(() => qaSetPadConnected(0, false));
        await page.waitForFunction(() => GnomHost.state.paused && GnomHost.state.disconnected?.includes(1));
        await checkFrozen(page);
        assert.ok(await page.locator('#local-resume').isDisabled(), 'Disconnected controller permits resume');
        await page.evaluate(() => qaSetPadConnected(0, true));
        await page.waitForFunction(() => GnomHost.state.disconnected?.length === 0
          && !document.querySelector('#local-resume').disabled);
        await resume(page);
      }
      await page.locator('.local-pause-button').click();
      await checkFrozen(page);
      await page.locator('#local-pause').getByRole('button', { name: 'Выйти', exact: true }).click();
      await page.waitForFunction(() => document.querySelector('#local-race').hidden);
      results.push({ count, layout, sectorColors, movement: true, pause: true, resume: true, recovery: true,
        disconnectReconnect: count > 1 ? true : 'not applicable', exit: true });
    }
    assert.deepEqual(errors, []);
    assert.deepEqual(api, []);
    assert.deepEqual(sockets, []);
    const environment = await page.evaluate(() => ({ userAgent: navigator.userAgent,
      viewport: { width: innerWidth, height: innerHeight }, devicePixelRatio,
      graphics: GnomHost.state?.graphics || null }));
    const report = { schemaVersion: 1, capturedAt: new Date().toISOString(), passed: true,
      url: url.href, browserVersion: browser.version(), headless, quality,
      browserFallback: 'Browser plugin not available', environment, results, measurement,
      virtualPads: true, physicalPads: false,
      measurementScope: 'Four human seats plus six bots near the start after brief keyboard movement, with human inputs released. Browser requestAnimationFrame intervals and published Godot tick delta; not GPU frame time, engine FPS, a worst-case race or a performance acceptance budget',
      errors, api, sockets };
    await fs.writeFile(path.join(output, 'result.json'), JSON.stringify(report, null, 2));
    console.log(`LOCAL_WEB_PASS ${JSON.stringify(report)}`);
  } catch (error) {
    await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {});
    const failure = { schemaVersion: 1, capturedAt: new Date().toISOString(), passed: false,
      message: error.message, results, errors, api, sockets, measurement };
    await fs.writeFile(path.join(output, 'failure.json'), JSON.stringify(failure, null, 2));
    await fs.writeFile(path.join(output, 'result.json'), JSON.stringify(failure, null, 2));
    throw error;
  } finally {
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
