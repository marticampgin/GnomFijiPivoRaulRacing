'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const root = path.resolve(__dirname, '../..');
const out = process.env.GNOM_QA_OUT || '/tmp';
const track = JSON.parse(fs.readFileSync(path.join(root, 'shared/track-manifest.json'), 'utf8'));
const widths = [{ width: 1280, height: 800 }, { width: 844, height: 390 }, { width: 390, height: 844 }, { width: 1600, height: 900 }];
const stylesheets = ['app.css', 'local-race.css', 'race-lobby.css', 'control-settings.css', 'ui-theme.css', 'race-overlays.css'];
const scripts = ['track-map.js', 'control-settings.js', 'race-lobby.js', 'local-race.js', 'menu-navigation.js', 'app.js'];
let checks = 0;
const failures = [];
const check = (condition, message) => { checks++; if (!condition) failures.push(message); };

async function fixture(browser, ready = true) {
  const page = await browser.newPage({ viewport: widths[0] });
  const errors = [], failedAssets = [], unexpected = [], expectedFailures = [];
  let merged = false, failTicket = false;
  const session = () => ({ csrfToken: 'fixture-only', user: { id: 'account-fixture', displayName: 'ОченьДлинноеИмяИгрокаБезПробелов', kind: 'account' }, mergeAvailable: !merged, devProfiles: [{ id: 'test-one', displayName: 'Игрок 1' }, { id: 'test-two', displayName: 'Игрок 2' }] });
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => {
    const expected = message.text().includes('Synthetic load failure') || (message.location().url.endsWith('/api/race/ticket') && message.text().includes('503'));
    if (message.type() === 'error' && !expected) errors.push(message.text());
  });
  page.on('response', response => {
    if (response.status() === 503 && response.url().endsWith('/api/race/ticket')) expectedFailures.push(response.url());
    else if (response.status() >= 400) failedAssets.push(response.url());
  });
  page.on('websocket', socket => unexpected.push(`WebSocket ${socket.url()}`));
  await page.addInitScript(() => {
    localStorage.setItem('gnom.music.v1', 'off');
    window.commands = [];
    window.fixturePads = [0, 1, 2].map(index => ({ index, id: `Fixture Xbox ${index + 1}`, mapping: 'standard', connected: true, axes: [0, 0], buttons: Array.from({ length: 17 }, () => ({ pressed: false, value: 0 })) }));
    Object.defineProperty(navigator, 'getGamepads', { value: () => fixturePads });
  });
  await page.route('**/*', route => {
    const url = new URL(route.request().url());
    if (url.origin !== 'http://localhost') { unexpected.push(url.href); return route.abort(); }
    if (url.pathname === '/') {
      let shell = fs.readFileSync(path.join(root, 'game/web/shell.html'), 'utf8').replace(/<script\b[^>]*>[\s\S]*?<\/script>/g, '').replace('$GODOT_HEAD_INCLUDE', '');
      shell = shell.replace(/<link\b[^>]*rel="stylesheet"[^>]*>/g, '').replace('</head>', `${stylesheets.map(file => `<link rel="stylesheet" href="/${file}">`).join('')}</head>`);
      return route.fulfill({ contentType: 'text/html', body: shell });
    }
    if (url.pathname === '/api/auth/bootstrap' || url.pathname === '/api/me') return route.fulfill({ json: session() });
    if (url.pathname === '/api/guest/merge') { merged = true; return route.fulfill({ json: { merged: true } }); }
    if (url.pathname === '/api/race/ticket') return failTicket ? route.fulfill({ status: 503, json: { error: 'unavailable' } }) : route.fulfill({ json: { styleId: 'drift', ticket: 'fixture-only', websocketUrl: 'ws://never-opened' } });
    const file = path.resolve(root, 'web', `.${url.pathname}`);
    if (file.startsWith(`${path.join(root, 'web')}${path.sep}`) && fs.existsSync(file) && fs.statSync(file).isFile()) return route.fulfill({ path: file });
    unexpected.push(url.pathname);
    return route.fulfill({ status: 404, body: '' });
  });
  await page.goto('http://localhost/');
  check(page.url() === 'http://localhost/' && /GNOM FIJI/i.test(await page.title()), 'Fixture page identity');
  check(/GNOM\s+FIJI/i.test(await page.locator('#hub h1').innerText()), 'Meaningful hub content renders');
  for (const file of scripts) await page.addScriptTag({ path: path.join(root, 'web', file) });
  if (ready) await page.evaluate(() => GnomHost.register(message => commands.push(JSON.parse(message))));
  return { page, errors, failedAssets, unexpected, expectedFailures, setTicketFailure: value => { failTicket = value; } };
}

async function capture(page, name, selector) {
  await page.waitForFunction(() => [...document.images].filter(image => image.getClientRects().length && image.getAttribute('src')).every(image => image.complete));
  const missingImages = await page.evaluate(() => [...document.images].filter(image => image.getClientRects().length && image.getAttribute('src') && !image.naturalWidth).map(image => image.src));
  check(missingImages.length === 0, `${name}: missing images ${missingImages.join('; ')}`);
  const bounds = await page.locator(selector).evaluate(node => {
    const rect = node.getBoundingClientRect();
    const visible = element => { const r = element.getBoundingClientRect(), style = getComputedStyle(element); return r.width > 0 && r.height > 0 && style.visibility !== 'hidden' && style.display !== 'none'; };
    const textOverflow = [...node.querySelectorAll('button, h1, h2, h3, strong, output')].filter(element => visible(element) && element.scrollWidth > element.clientWidth + 2).map(element => `${element.id || element.className}: ${element.textContent}`);
    return { left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom, viewport: innerWidth, overflow: node.scrollWidth - node.clientWidth, textOverflow };
  });
  check(bounds.left >= -1 && bounds.right <= bounds.viewport + 1 && bounds.overflow <= 1, `${name}: root horizontal bounds ${JSON.stringify(bounds)}`);
  check(bounds.textOverflow.length === 0, `${name}: text overflow ${bounds.textOverflow.join('; ')}`);
  const controlOverlap = await page.locator(selector).evaluate(node => [...node.querySelectorAll('.control-settings')].some(editor => {
    const reset = editor.querySelector('.control-settings-reset').getBoundingClientRect();
    return [...editor.querySelectorAll('select')].some(select => {
      const field = select.getBoundingClientRect();
      return field.width && field.height && Math.min(field.right, reset.right) - Math.max(field.left, reset.left) > 1 && Math.min(field.bottom, reset.bottom) - Math.max(field.top, reset.top) > 1;
    });
  }));
  check(!controlOverlap, `${name}: reset action overlaps visible control scheme`);
  if (selector === '#hud') {
    const overlaps = await page.locator('#hud').evaluate(node => {
      const pairs = [];
      for (const selector of [':scope > .participants, :scope > .racers, :scope > .lap-time, :scope > .minimap, :scope > .race-tools, :scope > .connection, :scope > .drift, :scope > .speed, :scope > .combat-hud', '.combat-hud > div']) {
        const panels = [...node.querySelectorAll(selector)].filter(panel => { const r = panel.getBoundingClientRect(); return r.width && r.height; });
        for (let i = 0; i < panels.length; i++) for (let j = i + 1; j < panels.length; j++) {
          const a = panels[i].getBoundingClientRect(), b = panels[j].getBoundingClientRect();
          if (Math.min(a.right, b.right) - Math.max(a.left, b.left) > 1 && Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 1) pairs.push(`${panels[i].className}/${panels[j].className}`);
        }
      }
      return pairs;
    });
    check(overlaps.length === 0, `${name}: panel overlap ${overlaps.join('; ')}`);
  }
  await page.screenshot({ path: path.join(out, `gnom-ui-${name}.png`) });
}

async function responsiveCapture(page, name, selector) {
  for (const viewport of widths) {
    await page.setViewportSize(viewport);
    await page.locator(selector).evaluate(node => node.scrollTop = 0);
    await capture(page, `${name}-${viewport.width}`, selector);
    if (name === 'hub-error') {
      check(await page.locator('#load-state').isHidden(), `Failed load hides stalled progress at ${viewport.width}`);
      if (viewport.width === 844) {
        const visibleError = await page.locator('#hub-error').evaluate(node => {
          const error = node.getBoundingClientRect(), content = node.closest('.hub-content').getBoundingClientRect(), footer = document.querySelector('.hub-footer').getBoundingClientRect();
          return error.top >= Math.max(0, content.top) && error.bottom <= Math.min(content.bottom, footer.top);
        });
        check(visibleError, 'Load failure is visible in the short landscape viewport');
      }
    }
    if (name === 'hub-ready' && viewport.width === 390) {
      await page.setViewportSize({ width: 390, height: 640 });
      await page.locator('#online-button').evaluate(node => node.scrollIntoView({ block: 'end' }));
      const scroll = await page.locator('#hub').evaluate(node => {
        const button = document.querySelector('#online-button').getBoundingClientRect(), footer = node.querySelector('.hub-footer').getBoundingClientRect();
        return { top: node.scrollTop, buttonTop: button.top, buttonBottom: button.bottom, footerTop: footer.top };
      });
      check(scroll.top > 0 && scroll.buttonTop >= 0 && scroll.buttonBottom <= scroll.footerTop, `Mobile menu scroll reaches its last command above the fixed footer: ${JSON.stringify(scroll)}`);
      await capture(page, 'hub-ready-scrolled-390x640', '#hub');
    }
  }
  await page.setViewportSize(widths[0]);
}

async function contrast(page, selector, label) {
  const ratio = await page.locator(selector).evaluate(node => {
    const rgb = value => value.match(/[\d.]+/g)?.slice(0, 3).map(Number);
    const luminance = value => rgb(value).map(channel => { const v = channel / 255; return v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4; }).reduce((sum, channel, index) => sum + channel * [.2126, .7152, .0722][index], 0);
    let surface = node;
    while (surface.parentElement && (getComputedStyle(surface).backgroundColor.match(/[\d.]+/g)?.[3] === '0')) surface = surface.parentElement;
    const style = getComputedStyle(node), foreground = luminance(style.color), background = luminance(getComputedStyle(surface).backgroundColor);
    return (Math.max(foreground, background) + .05) / (Math.min(foreground, background) + .05);
  });
  check(ratio >= 4.5, `${label}: text contrast ${ratio.toFixed(2)}`);
}

function localState(count, extra = {}) {
  return { mode: 'local', phase: 'racing', paused: false, countdown: 0, layout: 'side-by-side', devices: [{ id: 0, name: 'Xbox' }, { id: 1, name: 'Xbox 2' }, { id: 2, name: 'Xbox 3' }], trackDescriptor: track, graphics: { quality: 'standard', reducedEffects: false },
    seats: Array.from({ length: count }, (_, index) => ({ id: index + 1, device: index - 1, styleId: ['handling', 'acceleration', 'speed', 'drift'][index], health: 84, maxHealth: 100, lap: 2, rank: index + 1, speed: 127, elapsed: 94.525, shards: 12, effects: { crystal_shield: { remaining: 8 } }, items: ['seeker', 'rear_trap'], canUseItems: true, driftLevel: 2, driftSegments: [1, 1, 0], drift: .75, driftActive: true, driftOwner: -1, driftFeedback: 'ready' })),
    players: Array.from({ length: 10 }, (_, index) => ({ id: index + 1, name: index < count ? `P${index + 1}` : `Бот ${index + 1}`, rank: index + 1, worldPosition: [0, 0, 0] })), ...extra };
}

async function seedLocal(page, state) { await page.evaluate(state => GnomHost.update(JSON.stringify(state)), state); }

(async () => {
  fs.mkdirSync(out, { recursive: true });
  for (const file of stylesheets) assert.ok(fs.existsSync(path.join(root, 'web', file)), `Missing stylesheet ${file}`);
  const browser = await chromium.launch({ headless: true });
  const fixtures = [];
  try {
    const hub = await fixture(browser, false); fixtures.push(hub);
    let page = hub.page;
    await page.evaluate(() => {
      window.Engine = class {
        static getMissingFeatures() { return []; }
        startGame({ onProgress }) { onProgress(37, 100); return new Promise((_, reject) => { window.failLoading = () => reject(new Error('Synthetic load failure')); }); }
      };
      GnomHost.boot({});
    });
    check(await page.locator('#local-button').isDisabled(), 'Loading blocks race start');
    await responsiveCapture(page, 'hub-loading', '#hub');
    await page.evaluate(() => failLoading());
    await page.waitForFunction(() => !document.querySelector('#hub-error').hidden);
    await responsiveCapture(page, 'hub-error', '#hub');
    await page.evaluate(() => { document.querySelector('#hub-error').hidden = true; GnomHost.register(message => commands.push(JSON.parse(message))); });
    await page.waitForFunction(() => document.activeElement.id === 'local-button');
    await responsiveCapture(page, 'hub-ready', '#hub');
    await contrast(page, '#local-button', 'Hub primary action');
    const confirmGreen = await page.locator('#hub .menu-hints kbd[data-key="A"]').evaluate(node => {
      const rgb = getComputedStyle(node).backgroundColor.match(/[\d.]+/g).slice(0, 3).map(Number);
      return rgb[1] > rgb[0] && rgb[1] > rgb[2];
    });
    check(confirmGreen, 'Hub gamepad A hint is green, not the Back button color');

    await page.locator('#settings-button').click();
    await responsiveCapture(page, 'settings', '#settings-dialog');
    await page.evaluate(() => { fixturePads[0].buttons[13].pressed = true; });
    await page.waitForTimeout(80);
    await page.evaluate(() => { fixturePads[0].buttons[13].pressed = false; });
    await page.waitForTimeout(80);
    check((await page.locator('#settings-dialog .control-bindings').innerText()).includes('LB / RB'), 'Settings switch to the active gamepad bindings');
    await responsiveCapture(page, 'settings-gamepad', '#settings-dialog');
    await page.keyboard.press('Tab');
    check((await page.locator('#settings-dialog .control-bindings').innerText()).includes('Space / C'), 'Settings return to keyboard bindings');
    await page.locator('#settings-dialog [data-control="steering"]').focus();
    const steering = await page.locator('#settings-dialog [data-control="steering"]').inputValue();
    await page.keyboard.press('ArrowRight');
    check(Number(await page.locator('#settings-dialog [data-control="steering"]').inputValue()) > Number(steering), 'Settings sensitivity adjusts by keyboard');
    await page.keyboard.press('Escape');
    check(!await page.locator('#settings-dialog').evaluate(node => node.open), 'Settings Back closes dialog');

    await page.locator('#profile-button').click();
    await page.waitForFunction(() => document.querySelector('#profile-dialog').open);
    await responsiveCapture(page, 'profile', '#profile-dialog');
    check(await page.locator('#merge-button').isDisabled(), 'Merge requires explicit checkbox');
    await page.locator('#merge-confirm').check();
    check(await page.locator('#merge-button').isEnabled(), 'Merge can be confirmed');
    await page.locator('#merge-button').click();
    await page.waitForFunction(() => document.querySelector('#profile-feedback').textContent === 'Прогресс перенесён');
    check(await page.locator('#merge-section').isHidden(), 'Successful merge clears the transfer option');
    await page.keyboard.press('Escape');

    await page.locator('#online-button').click();
    await responsiveCapture(page, 'online-setup', '#online-setup');
    await page.locator('input[name="driving-style"][value="drift"]').check();
    check(await page.locator('#selected-style').innerText() === 'Дрифт', 'Network style choice remains functional');
    hub.setTicketFailure(true);
    await page.locator('#join-button').click();
    await page.waitForFunction(() => !document.querySelector('#online-error').hidden);
    check(await page.locator('#online-setup').evaluate(node => node.open), 'Failed online join keeps its setup open');
    await responsiveCapture(page, 'online-error', '#online-setup');
    hub.setTicketFailure(false);
    await page.locator('#join-button').click();
    await page.waitForFunction(() => !document.querySelector('#hud').hidden);
    check(await page.evaluate(() => commands.some(command => command.type === 'join' && command.url === 'ws://never-opened')), 'Online join reaches only the stub receiver');
    const network = { status: 'racing', phase: 'racing', raceId: 'fixture-race', playerId: 1, styleId: 'drift', players: Array.from({ length: 10 }, (_, index) => ({ id: index + 1, position: index + 1, name: index ? `ДлинноеИмяСоперника${index + 1}` : 'Вы', isBot: index > 0, connected: true, elapsed: 123.456 + index, worldPosition: [0, 0, 0] })), speed: 127, lap: 2, elapsed: 123.456, ping: 42, countdown: 0, health: 84, shards: 12, items: ['seeker', 'rear_trap'], canUseItems: true, effects: { crystal_shield: { remaining: 8 } }, drift: .8, driftLevel: 2, driftSegments: [1, 1, 0], driftActive: true, driftOwner: -1, driftFeedback: 'ready', track };
    await page.evaluate(state => GnomHost.update(JSON.stringify(state)), network);
    await responsiveCapture(page, 'online-hud', '#hud');
    await page.locator('#menu-button').click();
    await responsiveCapture(page, 'online-menu', '#menu-dialog');
    await page.locator('#resume-button').click();
    check(!await page.locator('#menu-dialog').evaluate(node => node.open), 'Online resume closes menu');
    for (const status of ['disconnected', 'update_required']) {
      await page.evaluate(state => GnomHost.update(JSON.stringify(state)), { ...network, status });
      await responsiveCapture(page, status, '#disconnect');
      if (status === 'disconnected') {
        hub.setTicketFailure(true);
        await page.locator('#reconnect-button').click();
        await page.waitForFunction(() => !document.querySelector('#disconnect-feedback').hidden);
        await responsiveCapture(page, 'reconnect-error', '#disconnect');
        check(await page.locator('#reconnect-button').isEnabled(), 'Reconnect error permits retry');
        hub.setTicketFailure(false);
        await page.evaluate(state => GnomHost.update(JSON.stringify(state)), network);
        check(await page.locator('#disconnect-feedback').isHidden(), 'Healthy connection clears reconnect error');
        await page.evaluate(state => GnomHost.update(JSON.stringify(state)), { ...network, status: 'disconnected' });
        check(await page.locator('#disconnect-feedback').isHidden(), 'A later disconnect does not revive stale feedback');
        hub.setTicketFailure(true);
        await page.locator('#reconnect-button').click();
        await page.waitForFunction(() => !document.querySelector('#disconnect-feedback').hidden);
        hub.setTicketFailure(false);
      }
      if (status === 'update_required') check(await page.locator('#disconnect-feedback').isHidden(), 'Update-required state clears previous reconnect failure');
    }
    await page.evaluate(state => GnomHost.update(JSON.stringify(state)), { ...network, phase: 'results', status: 'results', finished: true, canRestart: true, players: network.players.map(player => ({ ...player, finished: true, dnf: player.id === 10 })) });
    await responsiveCapture(page, 'online-results', '#result-dialog');
    check(await page.locator('#result-racers li').count() === 10, 'Online results retain all ten racers');
    await page.locator('#restart-button').click();
    check(await page.evaluate(() => commands.some(command => command.type === 'restart' && command.race_id === 'fixture-race')), 'Repeat command retains race identity');
    await page.locator('#result-exit').click();
    check(await page.locator('#hub').isVisible(), 'Results exit returns to hub');
    check(hub.expectedFailures.length === 3, 'Exactly three intentional ticket failures exercised');

    const local = await fixture(browser); fixtures.push(local); page = local.page;
    await seedLocal(page, localState(2, { paused: true }));
    await page.waitForFunction(() => document.querySelector('#local-pause').open);
    await responsiveCapture(page, 'local-pause', '#local-pause');
    await contrast(page, '#local-resume', 'Pause primary action');
    await page.locator('#local-pause').getByRole('button', { name: 'Настройки', exact: true }).click();
    await responsiveCapture(page, 'local-settings', '#local-settings');
    await page.locator('#local-settings details summary').first().click();
    await contrast(page, '#local-settings details[open] summary', 'Expanded player controls summary');
    await responsiveCapture(page, 'local-controls-expanded', '#local-settings');
    await page.keyboard.press('Escape');
    check(await page.locator('#local-pause').evaluate(node => node.open), 'Nested local settings return to pause');
    await seedLocal(page, localState(2, { paused: true, disconnected: [1], devices: [{ id: 1, name: 'Replacement pad' }] }));
    check(await page.locator('#local-resume').isDisabled(), 'Disconnected participant prevents resume');
    await responsiveCapture(page, 'local-disconnected', '#local-settings');

    for (const count of [1, 2, 3, 4]) {
      const state = localState(count);
      await seedLocal(page, state);
      for (const viewport of widths.filter(viewport => viewport.width !== 844)) {
        await page.setViewportSize(viewport);
        await capture(page, `local-hud-${count}-${viewport.width}`, '#local-race');
        check(await page.locator('.local-pane').count() === count, `Local HUD retains ${count} sectors at ${viewport.width}`);
        check(await page.locator('button.local-slot').count() === count && await page.locator('.local-slot-next:not(button)').count() === count, `Local FIFO inventory at ${count}/${viewport.width}`);
      }
      await seedLocal(page, { ...state, phase: 'results', seats: state.seats.map(seat => ({ ...seat, finished: true, canUseItems: false, dnf: seat.id === count && count > 1 })) });
      for (const viewport of widths) {
        await page.setViewportSize(viewport);
        await capture(page, `local-results-${count}-${viewport.width}`, '#local-race');
        const inside = await page.locator('.local-finish').evaluateAll(nodes => nodes.every(node => { const r = node.getBoundingClientRect(), p = node.parentElement.getBoundingClientRect(); return r.left >= p.left - 1 && r.right <= p.right + 1 && r.top >= p.top - 1 && r.bottom <= p.bottom + 1; }));
        check(inside, `Local results fit sector ${count}/${viewport.width}`);
      }
    }
    await page.setViewportSize(widths[0]);
    await seedLocal(page, localState(1, { tutorial: { step: 'drift', stage: 3, total: 5, progress: .72, complete: false } }));
    await responsiveCapture(page, 'tutorial-active', '#local-race');
    await seedLocal(page, localState(1, { tutorial: { step: 'items', stage: 5, total: 5, progress: 1, complete: true } }));
    await responsiveCapture(page, 'tutorial-complete', '#local-race');
    await page.locator('.local-lesson').getByRole('button', { name: 'Повторить', exact: true }).click();
    check(await page.evaluate(() => commands.some(command => command.type === 'local_tutorial_retry')), 'Tutorial retry remains wired');
    for (const item of fixtures) {
      check(item.errors.length === 0, `Page errors: ${item.errors.join('; ')}`);
      check(item.failedAssets.length === 0, `Failed assets: ${item.failedAssets.join('; ')}`);
      check(item.unexpected.length === 0, `Unexpected requests: ${item.unexpected.join('; ')}`);
      check(!await item.page.evaluate(() => commands.some(command => command.type === 'local_start')), 'No real local race start requested');
    }
    const report = { checks, failures, browser: 'Playwright Chromium; Browser plugin not available', scope: 'Synthetic UI snapshots and menus only; no Godot boot, network race, or physical controller validation' };
    fs.writeFileSync(path.join(out, 'gnom-ui-report.json'), JSON.stringify(report, null, 2));
    console.log(JSON.stringify(report, null, 2));
    assert.deepEqual(failures, []);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
