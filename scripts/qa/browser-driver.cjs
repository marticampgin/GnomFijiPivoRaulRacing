const { chromium } = require('playwright');
const fs = require('node:fs/promises');
const path = require('node:path');
const assert = require('node:assert/strict');
const sharp = require('sharp');

const url = process.env.GNOM_DRIVER_URL || 'http://127.0.0.1:8788/';
const output = process.env.GNOM_DRIVER_OUT || '/tmp/gnom-browser-driver-qa';
const requiredLaps = Number(process.env.GNOM_DRIVER_LAPS || 3);
const durationSeconds = Number(process.env.GNOM_DRIVER_SECONDS || 240);
const maximumSpeed = Number(process.env.GNOM_DRIVER_SPEED || 24);
const tracePhysics = process.env.GNOM_DRIVER_TRACE === '1';
const verifyRepeat = process.env.GNOM_DRIVER_REPEAT === '1';
const viewport = { width: 1600, height: 900 };
const sourcePackage = path.resolve(__dirname, '../../game/track/baked/castle_waterfalls.json');
const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
const clamp = (x, low, high) => Math.max(low, Math.min(high, x));
const distance = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
const normal = v => { const n = Math.hypot(...v); return n > 1e-5 ? v.map(x => x / n) : [1, 0]; };

function routeFor(descriptor) {
  const points = descriptor?.minimap?.polyline;
  assert.ok(Array.isArray(points) && points.length > 3 && points.every(p => p.length === 2 && p.every(Number.isFinite)), 'A valid observable route descriptor is required');
  const offsets = [0];
  for (let i = 1; i < points.length; i++) offsets.push(offsets.at(-1) + distance(points[i - 1], points[i]));
  assert.ok(distance(points[0], points.at(-1)) < 0.01, 'Route must be closed');
  const length = offsets.at(-1);
  const at = s => {
    s = ((s % length) + length) % length;
    let i = 0;
    while (i + 2 < offsets.length && offsets[i + 1] < s) i++;
    const fraction = (s - offsets[i]) / (offsets[i + 1] - offsets[i]);
    return points[i].map((value, coordinate) => value + (points[i + 1][coordinate] - value) * fraction);
  };
  const project = position => {
    let best = { distance: Infinity, s: 0, tangent: [1, 0] };
    for (let i = 0; i < points.length - 1; i++) {
      const a = points[i], b = points[i + 1];
      const dx = b[0] - a[0], dz = b[1] - a[1];
      const fraction = clamp(((position[0] - a[0]) * dx + (position[1] - a[1]) * dz) / (dx * dx + dz * dz), 0, 1);
      const error = distance(position, [a[0] + dx * fraction, a[1] + dz * fraction]);
      if (error < best.distance) best = { distance: error, s: offsets[i] + (offsets[i + 1] - offsets[i]) * fraction, tangent: normal([dx, dz]) };
    }
    return best;
  };
  return { length, at, project };
}

function controlsFor(route, state, heading) {
  const position = [state.worldPosition[0], state.worldPosition[2]];
  const location = route.project(position);
  const speed = state.speed / 3.6;
  const lookAhead = 8 + Math.min(speed, 30) * 0.26;
  const target = route.at(location.s + lookAhead);
  const delta = [target[0] - position[0], target[1] - position[1]];
  const targetDistance = Math.max(2, Math.hypot(...delta));
  const error = Math.atan2(heading[0] * delta[1] - heading[1] * delta[0], heading[0] * delta[0] + heading[1] * delta[1]);
  const a = route.at(location.s + 6), b = route.at(location.s + 16), c = route.at(location.s + 26);
  const first = normal([b[0] - a[0], b[1] - a[1]]), second = normal([c[0] - b[0], c[1] - b[1]]);
  const bend = Math.abs(Math.atan2(first[0] * second[1] - first[1] * second[0], first[0] * second[0] + first[1] * second[1]));
  const curvature = bend / 10;
  let targetSpeed = clamp(1.32 * 0.8 / Math.max(0.001, curvature), 13, maximumSpeed);
  if (Math.abs(error) > 0.55 || location.distance > 4.0) targetSpeed = Math.min(targetSpeed, 14);
  const steering = clamp((2 * Math.max(speed, 5) * Math.sin(error) / targetDistance) / 1.32, -1, 1);
  return { steering, throttle: speed < targetSpeed - 0.3, brake: speed > targetSpeed + 1.5, targetSpeedMps: targetSpeed, speedMps: speed, error, s: location.s, centerError: location.distance };
}

async function canvasPixels(page) {
  const buffer = await page.locator('#canvas').screenshot();
  const { data, info } = await sharp(buffer).resize(160, 90).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  const colors = new Set();
  for (let i = 0; i < data.length; i += info.channels) colors.add(`${data[i] >> 4},${data[i + 1] >> 4},${data[i + 2] >> 4}`);
  return { colors: colors.size, data };
}

async function main() {
  const parsed = new URL(url);
  assert.ok(parsed.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(parsed.hostname), 'Only an exact local preview is allowed');
  assert.ok([1, 2, 3].includes(requiredLaps) && durationSeconds >= 10 && durationSeconds <= 900, 'Use 1..3 laps and 10..900 seconds');
  await fs.mkdir(output, { recursive: true });
  const browser = await chromium.launch({ headless: false });
  const context = await browser.newContext({ viewport });
  const page = await context.newPage();
  const errors = [], samples = [], anchorsCaptured = new Set();
  const physicsTrace = [];
  let tracePlayerId;
  if (tracePhysics) page.on('websocket', socket => {
    socket.on('framesent', ({ payload }) => {
      try {
        const packet = JSON.parse(String(payload));
        if (packet.type === 'input') physicsTrace.push({ at: Date.now(), input: packet });
      } catch {}
    });
    socket.on('framereceived', ({ payload }) => {
      try {
        const packet = JSON.parse(String(payload));
        const player = packet.players?.find(value => value.id === tracePlayerId);
        if (player) physicsTrace.push({ at: Date.now(), tick: packet.tick, ack: player.ack, state: player.state });
      } catch {}
    });
  });
  const report = { schemaVersion: 1, url, capturedAt: new Date().toISOString(), browser: browser.version(), viewport, browserRouting: 'Browser plugin not available; regular Playwright', scenario: 'Fresh guest, UI join, real keyboard-only route driving and observed authoritative HUD finish. No injected network inputs, teleportation, bot implementation or performance/capacity claim.', requiredLaps, durationSeconds, maximumSpeed, anchors: [], checks: {} };
  const held = new Set();
  const key = async (name, down) => {
    if (down && !held.has(name)) { await page.keyboard.down(name); held.add(name); }
    if (!down && held.has(name)) { await page.keyboard.up(name); held.delete(name); }
  };
  const release = async () => { for (const name of [...held]) await key(name, false); };
  const state = () => page.evaluate(() => {
    const value = window.GnomHost?.state;
    if (!value) return null;
    const { status, worldPosition, forward, speed, lap, finished, elapsed, countdown, ping, correction, fps, serverTick, track, playerId, players, raceId, phase, canRestart, repeatReady } = value;
    return { status, worldPosition, forward, speed, lap, finished, elapsed, countdown, ping, correction, fps, serverTick, track, playerId, players, raceId, phase, canRestart, repeatReady };
  });
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
  let last;
  try {
    await page.goto(url);
    await page.waitForFunction(() => !document.getElementById('join-button').disabled, undefined, { timeout: 90000 });
    report.title = await page.title();
    assert.match(report.title, /GNOM FIJI/i);
    report.checks.pageIdentity = true;
    await page.locator('#join-button').click();
    await page.waitForFunction(() => window.GnomHost.state?.status === 'racing' && window.GnomHost.state.countdown <= 0, undefined, { timeout: 45000 });
    await page.bringToFront();
    await page.locator('#canvas').click({ position: { x: viewport.width / 2, y: viewport.height / 2 } });
    last = await state();
    tracePlayerId = last.playerId;
    const route = routeFor(last.track);
    const initialLap = last.lap;
    report.initialState = last;
    report.track = { track_id: last.track.track_id, simulation_hash: last.track.simulation_hash, length: route.length };
    let anchors;
    const fixture = JSON.parse(await fs.readFile(sourcePackage, 'utf8'));
    if (fixture.simulation_hash === last.track.simulation_hash) anchors = fixture.camera_anchors.map(anchor => ({ id: anchor.id, position: [anchor.position[0], anchor.position[2]] }));
    else anchors = ['stone-start', 'forest', 'lake-waterfall', 'bridge-castle'].map((id, index) => ({ id, position: route.at([0.02, 0.23, 0.5, 0.77][index] * route.length) }));
    const before = await canvasPixels(page);
    assert.ok(before.colors > 30, 'Canvas is blank');
    report.checks.nonblankCanvas = { colors: before.colors };
    await page.screenshot({ path: path.join(output, 'start.png') });
    let heading = route.project([last.worldPosition[0], last.worldPosition[2]]).tangent;
    let previousPosition = last.worldPosition;
    let lastServerTick = last.serverTick;
    let lastProgressAt = Date.now();
    let lastLogAt = 0;
    const started = Date.now();
    while (Date.now() - started < durationSeconds * 1000) {
      const current = await state();
      if (!current || !['racing', 'finished'].includes(current.status)) throw new Error(`Race state changed unexpectedly: ${current?.status}`);
      if (current.status === 'finished' && current.finished !== true) throw new Error('Finished status is missing the authoritative finish flag');
      const elapsedMs = Date.now() - started;
      if (current.finished === true || (requiredLaps < 3 && current.lap >= initialLap + requiredLaps)) {
        last = current;
        report.completed = true;
        break;
      }
      if (current.serverTick !== lastServerTick) { lastServerTick = current.serverTick; lastProgressAt = Date.now(); }
      assert.ok(Date.now() - lastProgressAt < 5000, 'Server snapshots stopped');
      if (Array.isArray(current.forward) && current.forward.length === 3) {
        heading = normal([current.forward[0], current.forward[2]]);
        report.headingSource = 'observed HUD forward';
      } else {
        const movement = [current.worldPosition[0] - previousPosition[0], current.worldPosition[2] - previousPosition[2]];
        if (Math.hypot(...movement) > 0.15) heading = normal(movement);
        report.headingSource = 'observed position differences, initial route tangent';
      }
      previousPosition = current.worldPosition;
      const controls = controlsFor(route, current, heading);
      samples.push({ elapsedMs, position: current.worldPosition, forward: current.forward || null, lap: current.lap, finished: current.finished, speedKph: current.speed, serverTick: current.serverTick, correction: current.correction, fps: current.fps, ...controls });
      if (Date.now() - lastLogAt > 5000) {
        console.log(JSON.stringify({ elapsed: Math.round(elapsedMs / 1000), lap: current.lap, speed: Math.round(current.speed), s: Math.round(controls.s), centerError: +controls.centerError.toFixed(2), steering: +controls.steering.toFixed(2) }));
        lastLogAt = Date.now();
      }
      assert.ok(controls.centerError < 18, 'Driver left the route; test stops without recovery or teleport');
      for (const anchor of anchors) {
        if (!anchorsCaptured.has(anchor.id) && distance([current.worldPosition[0], current.worldPosition[2]], anchor.position) < 10) {
          await release();
          await page.screenshot({ path: path.join(output, `${anchor.id}.png`) });
          report.anchors.push({ id: anchor.id, elapsedMs, position: current.worldPosition, lap: current.lap });
          anchorsCaptured.add(anchor.id);
        }
      }
      await key('w', controls.throttle && !controls.brake);
      await key('s', controls.brake);
      const steerKey = controls.steering < 0 ? 'a' : 'd';
      await key(steerKey === 'a' ? 'd' : 'a', false);
      const pulse = Math.abs(controls.steering) < 0.025 ? 0 : Math.round(Math.abs(controls.steering) * 90);
      if (pulse > 0) { await key(steerKey, true); await delay(pulse); }
      await key(steerKey, false);
      await delay(Math.max(0, 90 - pulse));
      last = current;
    }
    await release();
    report.finalState = await state();
    report.serverFinish = report.finalState.finished === true;
    report.elapsedSeconds = (Date.now() - started) / 1000;
    report.completed = report.completed === true;
    assert.ok(report.completed, `Driver did not complete ${requiredLaps} lap(s) within ${durationSeconds}s`);
    const contactStops = samples.flatMap((sample, index) => {
      const previous = samples[index - 1];
      if (!previous) return [];
      const gap = sample.elapsedMs - previous.elapsedMs;
      const travel = Math.hypot(...sample.position.map((value, axis) => value - previous.position[axis]));
      return gap > 0 && gap <= 250 && previous.speedMps > 8 && sample.speedMps < previous.speedMps * 0.25
        && !previous.brake && !sample.brake && previous.centerError < 3.5 && sample.centerError < 3.5
        && travel < 4 && previous.lap === sample.lap
        ? [{ elapsedMs: sample.elapsedMs, s: sample.s, beforeMps: previous.speedMps, afterMps: sample.speedMps }]
        : [];
    });
    report.checks.contactStops = contactStops;
    assert.equal(contactStops.length, 0, 'Sudden unbraked speed loss near the road centre');
    if (requiredLaps === 3) {
      assert.equal(report.serverFinish, true, 'Three-lap test requires actual authoritative finish');
      await page.locator('#result-dialog[open]').waitFor({ timeout: 5000 });
    }
    await page.screenshot({ path: path.join(output, report.serverFinish ? 'server-finish.png' : 'driver-end.png'), timeout: 90000 });
    const after = await canvasPixels(page);
    const ratio = before.data.reduce((count, value, index) => count + (Math.abs(value - after.data[index]) > 10 ? 1 : 0), 0) / before.data.length;
    report.checks.changedCanvas = { ratio, colors: after.colors };
    assert.ok(ratio > 0.005, 'Canvas did not change');
    assert.equal(anchorsCaptured.size, 4, 'Four route anchor screenshots are required');
    if (verifyRepeat) {
      assert.equal(requiredLaps, 3, 'Repeat verification requires a full race');
      await page.waitForFunction(() => window.GnomHost.state.phase === 'results' && window.GnomHost.state.canRestart, undefined, { timeout: 45000 });
      const result = await state();
      report.terminalResult = result;
      assert.equal(result.players.length, 10, 'Result must contain the full grid');
      assert.equal(result.players.filter(player => player.isBot).length, 9, 'Fresh single-human race must have nine bots');
      assert.ok(result.players.every(player => player.finished || player.dnf), 'Every racer must have a terminal result');
      await page.screenshot({ path: path.join(output, 'results-grid.png') });
      await page.locator('#restart-button').click();
      await page.waitForFunction(id => window.GnomHost.state.raceId > id && window.GnomHost.state.phase === 'countdown', result.raceId, { timeout: 10000 });
      const repeated = await state();
      assert.equal(repeated.raceId, result.raceId + 1, 'One readiness action starts exactly one new generation');
      assert.equal(repeated.lap, 1);
      assert.equal(repeated.finished, false);
      assert.equal(repeated.elapsed, 0);
      assert.equal(await page.locator('#result-dialog').evaluate(dialog => dialog.open), false);
      await page.screenshot({ path: path.join(output, 'repeat-countdown.png') });
      report.checks.repeat = { previousRaceId: result.raceId, nextRaceId: repeated.raceId, racers: result.players.length, bots: 9 };
    }
    assert.deepEqual(errors, []);
    report.passed = true;
  } catch (error) {
    report.passed = false;
    report.failure = error.stack;
    report.finalState = await state().catch(() => last);
    await release().catch(() => {});
    await page.screenshot({ path: path.join(output, 'failure.png') }).catch(() => {});
    console.error(error.message);
    process.exitCode = 1;
  } finally {
    report.errors = errors;
    report.samples = samples;
    if (tracePhysics) await fs.writeFile(path.join(output, 'physics-trace.json'), JSON.stringify(physicsTrace));
    await fs.writeFile(path.join(output, 'result.json'), JSON.stringify(report, null, 2));
    await browser.close();
    console.log(JSON.stringify({ output, passed: report.passed, completed: report.completed, serverFinish: report.serverFinish, samples: samples.length, anchors: report.anchors, finalLap: report.finalState?.lap, errorCount: errors.length }));
  }
}

main().catch(error => { console.error(error); process.exitCode = 1; });
