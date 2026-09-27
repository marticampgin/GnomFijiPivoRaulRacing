const { chromium } = require('playwright');
const fs = require('node:fs/promises');
const sharp = require('sharp');
const assert = require('node:assert/strict');
const out = process.env.GNOM_QA_OUT || '/tmp/gnom-art-stage-qa';
const url = process.env.GNOM_QA_URL || 'http://127.0.0.1:8788/';
const profileFirst = Number(process.env.GNOM_QA_PROFILE_FIRST ?? 1);
const scope = process.env.GNOM_QA_SCOPE || 'full';

async function pixels(buffer) {
  const { data, info } = await sharp(buffer).resize(160, 90).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  const colors = new Set();
  for (let i = 0; i < data.length; i += info.channels) colors.add(`${data[i] >> 4},${data[i + 1] >> 4},${data[i + 2] >> 4}`);
  return { colors: colors.size, data };
}

async function contract(page) {
  return page.evaluate(() => {
    const state = window.GnomHost.state;
    return { playerId: state.playerId, profileName: state.players.find(player => player.id === state.playerId)?.name, lap: state.lap,
      trackId: state.track.track_id, trackSchema: state.track.schema_version, simulationRevision: state.track.simulation_revision, simulationHash: state.track.simulation_hash };
  });
}

async function graphics(page, quality, reducedEffects) {
  await page.getByRole('radio', { name: quality === 'low' ? 'Низкая' : 'Стандарт', exact: true }).check();
  await page.getByRole('checkbox', { name: 'Меньше эффектов', exact: true }).setChecked(reducedEffects);
  await page.waitForFunction(expected => {
    const actual = window.GnomHost.state?.graphics;
    return actual?.quality === expected.quality && actual.reducedEffects === expected.reducedEffects && Math.abs(actual.renderScale - expected.renderScale) < 0.001;
  }, { quality, reducedEffects, renderScale: quality === 'low' ? 0.75 : 1 });
  return page.evaluate(() => window.GnomHost.state.graphics);
}

async function recover(page) {
  await page.locator('#menu-button').click();
  await page.locator('#recover-button').click();
  await page.waitForFunction(() => window.GnomHost.state.speed < 2);
  await page.waitForTimeout(500);
}

async function heroSmoke(page, report) {
  const identity = await page.evaluate(() => ({ playerId: window.GnomHost.state.playerId, serverTick: window.GnomHost.state.serverTick }));
  assert.ok(identity.playerId, 'Hero smoke requires a joined player');
  const racing = async () => {
    await page.waitForFunction(expected => window.GnomHost.state.status === 'racing' && window.GnomHost.state.playerId === expected, identity.playerId, { timeout: 2000 });
    assert.equal(await page.locator('#disconnect').isVisible(), false, 'Hero is disconnected');
  };
  const screenshot = async name => {
    await racing();
    await page.screenshot({ path: `${out}/${name}.png` });
  };
  await racing();
  const before = await page.evaluate(() => window.GnomHost.state.forward);
  try {
    await page.keyboard.down('w');
    await page.waitForFunction(() => window.GnomHost.state.speed > 15, undefined, { timeout: 10000 });
    await page.keyboard.down('d');
    await page.waitForFunction(initial => {
      const forward = window.GnomHost.state.forward;
      return Math.hypot(forward[0] - initial[0], forward[2] - initial[2]) > 0.06;
    }, before, { timeout: 3000 });
    report.checks.steering = await page.evaluate(() => ({ speed: window.GnomHost.state.speed, forward: window.GnomHost.state.forward }));
    await screenshot('hero-steering');
  } finally {
    await page.keyboard.up('d');
    await page.keyboard.up('w');
  }
  await recover(page);
  await screenshot('hero-rear');
  try {
    await page.keyboard.down('c');
    await page.waitForTimeout(500);
    await screenshot('hero-front');
  } finally {
    await page.keyboard.up('c');
  }
  const unchanged = await contract(page);
  await page.locator('#menu-button').click();
  report.checks.low = await graphics(page, 'low', true);
  assert.deepEqual(await contract(page), unchanged);
  await page.locator('#resume-button').click();
  await page.waitForTimeout(400);
  await screenshot('hero-low');
  await page.locator('#menu-button').click();
  await graphics(page, 'standard', false);
  await page.locator('#resume-button').click();
  report.checks.viewports = [];
  for (const [width, height] of [[390, 844], [844, 390]]) {
    await page.setViewportSize({ width, height });
    await page.waitForTimeout(400);
    const canvas = await pixels(await page.locator('#canvas').screenshot());
    assert.ok(canvas.colors > 30, `Blank hero view at ${width}x${height}`);
    await screenshot(`hero-${width}x${height}`);
    report.checks.viewports.push({ width, height, canvasColors: canvas.colors });
  }
  const serverTick = await page.evaluate(() => window.GnomHost.state.serverTick);
  assert.ok(serverTick > identity.serverTick, 'Hero smoke stopped receiving server snapshots');
  report.checks.joinedHero = { playerId: identity.playerId, startTick: identity.serverTick, endTick: serverTick };
  await page.locator('#menu-button').click();
  await page.locator('#exit-button').click();
}

async function driftAndBoost(page) {
  await recover(page);
  const before = await page.evaluate(() => window.GnomHost.state);
  const [x, , z] = before.worldPosition;
  const nearest = before.track.minimap.polyline.reduce((best, point) => Math.hypot(point[0] - x, point[1] - z) < Math.hypot(best[0] - x, best[1] - z) ? point : best);
  const [fx, , fz] = before.forward;
  const steer = (x - nearest[0]) * -fz + (z - nearest[1]) * fx > 0 ? 'a' : 'd';
  const samples = [];
  try {
    await page.keyboard.down('w');
    await page.waitForFunction(() => window.GnomHost.state.speed > 39, undefined, { timeout: 10000 });
    await page.keyboard.down('Space');
    await page.keyboard.down(steer);
    const started = Date.now();
    while (Date.now() - started < 950) {
      if (Date.now() - started > 250) await page.keyboard.up('w');
      const sample = await page.evaluate(() => ({ drift: window.GnomHost.state.drift, boost: window.GnomHost.state.boost, speed: window.GnomHost.state.speed }));
      samples.push(sample);
      if (sample.drift >= 0.25) break;
      await page.waitForTimeout(45);
    }
    assert.ok(samples.some(sample => sample.drift >= 0.25), `Keyboard drift never reached the boost threshold: ${JSON.stringify(samples)}`);
    await page.keyboard.up('Space');
    await page.keyboard.up(steer);
    await page.waitForFunction(() => window.GnomHost.state.boost > 0, undefined, { timeout: 2000 });
    const boost = await page.evaluate(() => ({ boost: window.GnomHost.state.boost, drift: window.GnomHost.state.drift, playerId: window.GnomHost.state.playerId, speed: window.GnomHost.state.speed }));
    assert.equal(boost.playerId, before.playerId);
    await page.screenshot({ path: `${out}/keyboard-drift-boost.png` });
    await recover(page);
    return { samples, boost, steeringKey: steer, recovered: true };
  } finally {
    for (const key of ['w', 'a', 'd', 'Space']) await page.keyboard.up(key).catch(() => {});
  }
}

async function freezeAndResume(page) {
  await recover(page);
  const cdp = await page.context().newCDPSession(page);
  try {
    await page.keyboard.down('w');
    await page.waitForFunction(() => window.GnomHost.state.speed > 12, undefined, { timeout: 10000 });
    const before = await page.evaluate(() => ({ playerId: window.GnomHost.state.playerId, status: window.GnomHost.state.status, serverTick: window.GnomHost.state.serverTick, speed: window.GnomHost.state.speed }));
    await cdp.send('Page.setWebLifecycleState', { state: 'frozen' });
    await new Promise(resolve => setTimeout(resolve, 7000));
    await cdp.send('Page.setWebLifecycleState', { state: 'active' });
    await page.waitForFunction(expected => window.GnomHost.state.status === 'racing' && window.GnomHost.state.playerId === expected.playerId && window.GnomHost.state.serverTick > expected.serverTick + 120, before, { timeout: 10000 });
    const resumed = await page.evaluate(() => ({ playerId: window.GnomHost.state.playerId, status: window.GnomHost.state.status, serverTick: window.GnomHost.state.serverTick, speed: window.GnomHost.state.speed, pendingInputs: window.GnomHost.state.pendingInputs }));
    await page.waitForTimeout(1000);
    const settled = await page.evaluate(() => ({ playerId: window.GnomHost.state.playerId, status: window.GnomHost.state.status, serverTick: window.GnomHost.state.serverTick, speed: window.GnomHost.state.speed, pendingInputs: window.GnomHost.state.pendingInputs }));
    assert.equal(settled.playerId, before.playerId);
    assert.equal(settled.status, 'racing');
    assert.ok(settled.serverTick > resumed.serverTick, 'Fresh server snapshots did not continue after resume');
    assert.ok(settled.speed <= before.speed + 8 && settled.speed <= resumed.speed + 8, `Acceleration remained latched after freeze: ${JSON.stringify({ before, resumed, settled })}`);
    await page.keyboard.up('w');
    await page.screenshot({ path: `${out}/freeze-resume.png` });
    await recover(page);
    return { frozenMilliseconds: 7000, before, resumed, settled, recovered: true };
  } finally {
    await cdp.send('Page.setWebLifecycleState', { state: 'active' }).catch(() => {});
    await page.keyboard.up('w').catch(() => {});
    await cdp.detach().catch(() => {});
  }
}

async function menuAccessibility(page, width, height) {
  const menu = page.getByRole('dialog', { name: 'Гонка продолжается', exact: true });
  await menu.waitFor({ state: 'visible' });
  assert.equal(await menu.getByRole('group', { name: 'Графика', exact: true }).count(), 1);
  assert.equal(await menu.getByRole('radio', { name: 'Стандарт', exact: true }).count(), 1);
  assert.equal(await menu.getByRole('radio', { name: 'Низкая', exact: true }).count(), 1);
  assert.equal(await menu.getByRole('checkbox', { name: 'Меньше эффектов', exact: true }).count(), 1);
  const bounds = await menu.boundingBox();
  assert.ok(bounds.x >= -1 && bounds.y >= -1 && bounds.x + bounds.width <= width + 1 && bounds.y + bounds.height <= height + 1, `Menu outside ${width}x${height}: ${JSON.stringify(bounds)}`);
  const metrics = await menu.evaluate(element => ({ clientWidth: element.clientWidth, scrollWidth: element.scrollWidth, clientHeight: element.clientHeight, scrollHeight: element.scrollHeight }));
  assert.ok(metrics.scrollWidth <= metrics.clientWidth + 1, 'Menu has horizontal overflow');
  await page.screenshot({ path: `${out}/menu-${width}x${height}.png` });
  const controls = ['.close-dialog', '#resume-button', '#recover-button', 'input[value="standard"]', 'input[value="low"]', '#reduced-effects', '#exit-button'];
  const controlBounds = [];
  for (const selector of controls) {
    const control = menu.locator(selector);
    await control.scrollIntoViewIfNeeded();
    const rectangle = await control.boundingBox();
    assert.ok(rectangle && rectangle.x >= bounds.x - 1 && rectangle.x + rectangle.width <= bounds.x + bounds.width + 1 && rectangle.y >= bounds.y - 1 && rectangle.y + rectangle.height <= bounds.y + bounds.height + 1, `Menu control is unreachable or clipped: ${selector}`);
    controlBounds.push({ selector, ...rectangle });
  }
  await menu.locator('.close-dialog').focus();
  const focusOrder = [];
  for (let index = 0; index < 9; index++) {
    await page.keyboard.press('Tab');
    const focus = await page.evaluate(() => ({ inside: document.getElementById('menu-dialog').contains(document.activeElement), documentFocused: document.hasFocus(), id: document.activeElement.id, tag: document.activeElement.tagName, value: document.activeElement.value || null }));
    focusOrder.push(focus);
    const browserChrome = !focus.documentFocused && focus.tag === 'BODY' && focus.id === '';
    assert.ok(focus.inside || browserChrome, `Keyboard focused the game background while the menu is modal: ${JSON.stringify(focusOrder)}`);
  }
  assert.equal(await menu.evaluate(element => element.matches(':modal')), true);
  let backgroundBlocked = false;
  try {
    await page.locator('#menu-button').click({ trial: true, timeout: 350 });
  } catch (error) {
    if (error.name !== 'TimeoutError') throw error;
    backgroundBlocked = true;
  }
  assert.ok(backgroundBlocked, 'Game background button became clickable while the menu was modal');
  return { bounds, metrics, controlBounds, focusOrder, accessibleLabels: true, backgroundBlocked };
}

(async () => {
  const parsedUrl = new URL(url);
  assert.ok(parsedUrl.protocol === 'http:' && ['127.0.0.1', 'localhost'].includes(parsedUrl.hostname), 'Only a local preview URL is allowed');
  assert.ok(profileFirst === 0 || profileFirst === 1, 'GNOM_QA_PROFILE_FIRST must be 0 or 1');
  assert.ok(['full', 'hero'].includes(scope), 'GNOM_QA_SCOPE must be full or hero');
  await fs.mkdir(out, { recursive: true });
  const browser = await chromium.launch({ headless: false });
  const errors = [], contexts = [], functionalFailures = [];
  let activePage;
  const report = { url, capturedAt: new Date().toISOString(), browser: browser.version(), browserRouting: 'Browser plugin not available; regular Playwright', profileOrder: [profileFirst, 1 - profileFirst],
    scenario: 'Authored-route art study/blockout, not accepted final production art. Two dev profiles, keyboard movement/drift/boost, recovery/look-back, CDP freeze/resume, graphics preferences, persistence, responsive HUD/menu and incompatible-version rejection. Full-lap acceptance runs in a separate keyboard-driver report; no mobile-controls or performance/capacity claim.', checks: {} };
  const started = Date.now();
  report.scope = scope;
  if (scope === 'hero') {
    report.profileOrder = [profileFirst];
    report.scenario = 'Focused hero geometry/material smoke: one profile, short keyboard movement/turn, front/rear views, Low and mobile framing. No laps, finish, drift, reconnect or performance acceptance.';
  }
  const ready = async page => page.waitForFunction(() => !document.querySelector('#join-button').disabled, undefined, { timeout: 90000 });
  const open = async profile => {
    const context = await browser.newContext({ viewport: { width: 1600, height: 900 }, reducedMotion: 'no-preference' }); contexts.push(context);
    const page = await context.newPage();
    page.on('pageerror', error => errors.push(error.message));
    page.on('console', entry => { if (entry.type() === 'error') errors.push(entry.text()); });
    await page.goto(url); await ready(page);
    await page.locator('#profile-button').click();
    await page.locator('#profile-list button').nth(profile).click();
    await page.getByText('Вход выполнен', { exact: true }).waitFor();
    await page.locator('#profile-dialog .close-dialog').click();
    return page;
  };
  const join = async page => {
    await page.locator('#join-button').click();
    await page.waitForFunction(() => window.GnomHost.state?.status === 'racing', undefined, { timeout: 30000 });
  };
  try {
    const page = await open(profileFirst); activePage = page;
    report.title = await page.title(); assert.match(report.title, /GNOM FIJI/i);
    assert.equal(new URL(page.url()).origin, new URL(url).origin);
    report.checks.pageIdentity = true;
    // Load both clients before the shared start; late arrivals now spectate this race.
    const p2 = scope === 'full' ? await open(1 - profileFirst) : null;
    if (p2) {
      await page.locator('#join-button').click();
      await p2.locator('#join-button').click();
      await page.waitForFunction(() => window.GnomHost.state?.status === 'racing', undefined, { timeout: 30000 });
      await p2.waitForFunction(() => window.GnomHost.state?.status === 'racing', undefined, { timeout: 30000 });
    } else {
      await join(page);
    }
    await page.bringToFront(); await page.waitForTimeout(1500);
    const first = await page.evaluate(() => window.GnomHost.state);
    assert.equal(first.track.track_id, 'castle-waterfalls');
    report.track = first.track;
    const canvas = page.locator('#canvas');
    const before = await pixels(await canvas.screenshot({ path: `${out}/desktop-start.png` }));
    assert.ok(before.colors > 30, `Blank canvas: ${before.colors} colors`);
    await page.keyboard.down('w');
    await page.waitForFunction(() => window.GnomHost.state.speed > 10, undefined, { timeout: 10000 });
    await page.waitForTimeout(1500); await page.keyboard.up('w');
    const moved = await page.evaluate(() => window.GnomHost.state);
    const after = await pixels(await canvas.screenshot({ path: `${out}/desktop-moving.png` }));
    const changed = before.data.reduce((n, value, i) => n + (Math.abs(value - after.data[i]) > 10 ? 1 : 0), 0) / before.data.length;
    assert.ok(changed > 0.005, 'Canvas unchanged after driving');
    report.checks.canvas = { colors: before.colors, changedPixelChannelRatio: changed, speed: moved.speed };
    await page.locator('#menu-button').click(); await page.locator('#recover-button').click();
    await page.waitForTimeout(1000);
    report.checks.recover = await page.evaluate(() => ({ speed: window.GnomHost.state.speed, lap: window.GnomHost.state.lap }));
    assert.ok(report.checks.recover.speed < 2);
    if (scope === 'hero') {
      await heroSmoke(page, report);
      assert.equal(await page.locator('vite-error-overlay, nextjs-portal, #webpack-dev-server-client-overlay').count(), 0);
      report.checks.noFrameworkOverlay = true;
      assert.deepEqual(errors, []);
      report.errors = errors;
      report.passed = true;
      console.log(JSON.stringify({ output: out, scope, passed: true, elapsedSeconds: (Date.now() - started) / 1000 }));
      return;
    }
    await page.bringToFront();
    await page.waitForFunction(() => window.GnomHost.state.players.filter(p => p.connected && !p.isBot).length === 2);
    report.checks.twoProfiles = await page.evaluate(() => window.GnomHost.state.players.filter(player => player.connected && !player.isBot).map(player => ({ id: player.id, name: player.name, worldPosition: player.worldPosition })));
    assert.notEqual(report.checks.twoProfiles[0].id, report.checks.twoProfiles[1].id);
    const grid = await page.evaluate(() => ({ count: window.GnomHost.state.players.length, bots: window.GnomHost.state.players.filter(player => player.isBot).length, spectating: window.GnomHost.state.spectating }));
    assert.deepEqual(grid, { count: 10, bots: 8, spectating: false }, 'Both humans must enter before start, with bots filling the remaining grid');
    assert.equal(await p2.evaluate(() => window.GnomHost.state.spectating), false);
    report.checks.botFilledGrid = grid;
    await page.screenshot({ path: `${out}/desktop-two-profiles.png` });
    await page.keyboard.down('c'); await page.waitForTimeout(500);
    await page.screenshot({ path: `${out}/desktop-front.png` });
    await page.keyboard.up('c'); await page.waitForTimeout(500);
    await page.screenshot({ path: `${out}/desktop-chase-restored.png` });
    report.checks.lookBackPressedAndReleased = true;
    await p2.locator('#menu-button').click(); await p2.locator('#exit-button').click();
    await contexts[1].close(); await page.bringToFront();

    for (const [name, check] of [['driftBoost', driftAndBoost], ['freezeResume', freezeAndResume]]) {
      try {
        report.checks[name] = { passed: true, ...await check(page) };
      } catch (error) {
        functionalFailures.push({ check: name, message: error.message });
        report.checks[name] = { passed: false, error: error.stack };
        console.error(`${name}: ${error.message}`);
        await page.screenshot({ path: `${out}/${name}-failure.png` });
        await recover(page);
      }
    }

    const unchanged = await contract(page);
    report.checks.graphics = { unchangedContract: unchanged, transitions: [] };
    await page.locator('#menu-button').click();
    report.checks.graphics.transitions.push(await graphics(page, 'low', true));
    assert.deepEqual(await contract(page), unchanged, 'Low/reduced effects changed the racing contract');
    assert.deepEqual(await page.evaluate(() => JSON.parse(localStorage.getItem('gnom.graphics.v1'))), { quality: 'low', reducedEffects: true });
    await page.screenshot({ path: `${out}/graphics-low-menu.png` });
    await page.locator('#resume-button').click(); await page.waitForTimeout(300);
    await page.screenshot({ path: `${out}/graphics-low.png` });
    await page.locator('#menu-button').click();
    report.checks.graphics.transitions.push(await graphics(page, 'standard', false));
    assert.deepEqual(await contract(page), unchanged, 'Standard/full effects changed the racing contract');
    await page.locator('#resume-button').click(); await page.waitForTimeout(300);
    await page.screenshot({ path: `${out}/graphics-standard.png` });
    await page.locator('#menu-button').click();
    report.checks.graphics.transitions.push(await graphics(page, 'low', true));
    await page.reload(); await ready(page); await join(page);
    await page.waitForFunction(() => window.GnomHost.state.graphics?.quality === 'low' && window.GnomHost.state.graphics?.reducedEffects === true);
    assert.deepEqual(await contract(page), unchanged, 'Reload/rejoin did not preserve profile/lap/simulation identity');
    assert.deepEqual(await page.evaluate(() => JSON.parse(localStorage.getItem('gnom.graphics.v1'))), { quality: 'low', reducedEffects: true });
    await page.locator('#menu-button').click();
    assert.equal(await page.getByRole('radio', { name: 'Низкая', exact: true }).isChecked(), true);
    assert.equal(await page.getByRole('checkbox', { name: 'Меньше эффектов', exact: true }).isChecked(), true);
    report.checks.graphics.persistedAfterReload = await page.evaluate(() => window.GnomHost.state.graphics);
    await page.screenshot({ path: `${out}/graphics-persisted.png` });
    await graphics(page, 'standard', false);
    await page.locator('#resume-button').click();

    report.checks.viewports = [];
    for (const [width, height] of [[1600, 900], [390, 844], [844, 390]]) {
      await page.setViewportSize({ width, height }); await page.waitForTimeout(600);
      const bounds = await page.evaluate(() => [...document.querySelectorAll('#hud > .hud-panel, #hud > .race-tools')].filter(el => !el.hidden && getComputedStyle(el).display !== 'none').map(el => {
        const r = el.getBoundingClientRect(); return { className: el.className, x: r.x, y: r.y, right: r.right, bottom: r.bottom, width: r.width, height: r.height };
      }));
      assert.ok(bounds.every(r => r.x >= -1 && r.y >= -1 && r.right <= width + 1 && r.bottom <= height + 1), JSON.stringify(bounds));
      const overlaps = [];
      for (let i = 0; i < bounds.length; i++) for (let j = i + 1; j < bounds.length; j++) {
        const a = bounds[i], b = bounds[j];
        if (Math.min(a.right, b.right) > Math.max(a.x, b.x) + 1 && Math.min(a.bottom, b.bottom) > Math.max(a.y, b.y) + 1) overlaps.push([a.className, b.className]);
      }
      assert.equal(overlaps.length, 0, JSON.stringify(overlaps));
      await page.screenshot({ path: `${out}/${width}x${height}.png` });
      await page.locator('#menu-button').click();
      const menu = await menuAccessibility(page, width, height);
      await page.locator('#resume-button').click();
      assert.equal(await page.locator('#menu-dialog').isVisible(), false);
      await page.waitForFunction(() => document.activeElement.id === 'canvas', undefined, { timeout: 2000 });
      report.checks.viewports.push({ width, height, bounds, overlaps, menu });
    }
    await page.setViewportSize({ width: 1600, height: 900 });
    await page.locator('#menu-button').click(); await page.locator('#exit-button').click();
    await join(page);
    assert.equal((await page.evaluate(() => window.GnomHost.state)).playerId, first.playerId);
    report.checks.rejoin = true;
    await page.locator('#menu-button').click(); await page.locator('#exit-button').click();
    report.checks.rejectedVersions = [];
    for (const [name, incompatible] of [['wire-v1', { protocol_version: 1 }], ['collider-v2', { loadout_hash: 'prototype-v2' }]]) {
      await page.reload(); await ready(page);
      const handler = async route => {
        const response = await route.fetch(); const json = await response.json();
        Object.assign(json.compatibility, incompatible);
        await route.fulfill({ response, json });
      };
      await page.route('**/api/race/ticket', handler);
      await page.locator('#join-button').click();
      await page.waitForFunction(() => window.GnomHost.state?.status === 'update_required');
      assert.equal(await page.locator('#reconnect-button').innerText(), 'ОБНОВИТЬ ИГРУ');
      await page.screenshot({ path: `${out}/version-rejection-${name}.png` });
      report.checks.rejectedVersions.push(name);
      await page.unroute('**/api/race/ticket', handler);
    }
    report.checks.incompatibleLaunchRejected = true;
    assert.equal(await page.locator('vite-error-overlay, nextjs-portal, #webpack-dev-server-client-overlay').count(), 0);
    report.checks.noFrameworkOverlay = true;
    assert.deepEqual(functionalFailures, [], 'Independent gameplay checks failed; remaining UI checks were still exercised');
    assert.deepEqual(errors, []);
    report.errors = errors; report.passed = true;
    console.log(JSON.stringify({ output: out, passed: true, graphics: report.checks.graphics, viewports: report.checks.viewports.map(value => ({ width: value.width, height: value.height, overlaps: value.overlaps, menuBounds: value.menu.bounds })) }));
  } catch (error) {
    report.passed = false; report.failure = error.stack; report.errors = errors;
    if (activePage) await activePage.screenshot({ path: `${out}/failure.png` }).catch(() => {});
    console.error(error); process.exitCode = 1;
  } finally {
    report.elapsedSeconds = (Date.now() - started) / 1000;
    report.functionalFailures = functionalFailures;
    await fs.writeFile(`${out}/result.json`, JSON.stringify(report, null, 2));
    await browser.close();
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
