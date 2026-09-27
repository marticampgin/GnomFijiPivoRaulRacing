const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const track = JSON.parse(fs.readFileSync(path.join(root, 'shared/track-manifest.json'), 'utf8'));
track.minimap.shortcuts = [[track.minimap.polyline[0], track.minimap.polyline[Math.floor(track.minimap.polyline.length / 4)]]];

(async () => {
  const browser = await chromium.launch({ headless: true });
  let checks = 0;
  const check = (value, message) => { assert.ok(value, message); checks++; };
  try {
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.route('http://fixture/**', route => {
      const url = new URL(route.request().url());
      if (url.pathname === '/') return route.fulfill({ contentType: 'text/html', body: fs.readFileSync(path.join(root, 'game/web/shell.html'), 'utf8').replace(/<script\b[^>]*>[\s\S]*?<\/script>/g, '').replace('$GODOT_HEAD_INCLUDE', '') });
      if (url.pathname === '/api/auth/bootstrap') return route.fulfill({ json: { user: { displayName: 'QA', kind: 'guest' } } });
      if (url.pathname === '/api/race/ticket') return route.fulfill({ json: { styleId: 'drift', ticket: 'fixture', websocketUrl: 'ws://fixture' } });
      const file = path.join(root, 'web', url.pathname);
      if (fs.existsSync(file) && fs.statSync(file).isFile()) return route.fulfill({ path: file });
      return route.fulfill({ status: 404, body: '' });
    });
    await page.goto('http://fixture/');
    for (const file of ['track-map.js', 'control-settings.js', 'local-race.js', 'app.js']) await page.addScriptTag({ path: path.join(root, 'web', file) });
    await page.evaluate(() => { GnomHost.register(() => {}); window.localFixture = GnomLocalUI.create({ send() {} }); });
    const seat = { id: 1, device: -1, styleId: 'drift', health: 100, lap: 3, rank: 1, speed: 50, effects: {}, attackWarning: 'rear' };
    const sizes = [[1600, 900], [844, 390], [390, 844]];
    for (const [width, height] of sizes) {
      await page.setViewportSize({ width, height });
      for (const count of [1, 2, 3, 4]) for (const layout of count === 2 ? ['side-by-side', 'stacked'] : ['side-by-side']) {
        const state = { seats: Array.from({ length: count }, (_, i) => ({ ...seat, id: i + 1 })), layout, players: [], trackDescriptor: track, trackEvent: { phase: 'warning', remaining: 2.1 } };
        await page.evaluate(state => localFixture.update(state), state);
        const geometry = await page.evaluate(() => {
          const status = document.querySelector('.local-race:not([hidden]) .local-track-status');
          const r = status.getBoundingClientRect();
          const grid = document.querySelector('.local-race:not([hidden]) .local-grid').getBoundingClientRect();
          return { text: status.textContent, height: r.height, width: status.scrollWidth <= status.clientWidth, fullViewport: grid.top === 0 && grid.left === 0 && grid.bottom === innerHeight && grid.right === innerWidth, clear: [...document.querySelectorAll('.local-race:not([hidden]) .local-health, .local-race:not([hidden]) .local-speed, .local-race:not([hidden]) .local-drift')].every(node => node.getBoundingClientRect().bottom <= r.top) };
        });
        check(geometry.text === 'ТРАССА МЕНЯЕТСЯ · 3 с', 'Rounded warning countdown');
        check(geometry.height === 24 && geometry.width && geometry.clear && geometry.fullViewport, `Local HUD space ${width}x${height}, ${count}, ${layout}`);
        check(await page.evaluate(() => {
          const canvas = document.querySelector('.local-race:not([hidden]) .local-map');
          const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
          for (let i = 0; i < pixels.length; i += 4) if (pixels[i] === 100 && pixels[i + 1] === 227 && pixels[i + 2] === 219 && pixels[i + 3] > 0) return true;
          return false;
        }), 'Local minimap renders cyan shortcut');
        await page.evaluate(state => localFixture.update({ ...state, trackEvent: { phase: 'active', active: [false, true] } }), state);
        check(await page.locator('.local-race:not([hidden]) .local-track-status').textContent() === 'НОВЫЕ ПРЕПЯТСТВИЯ', 'Active indicator supports deferred bodies');
        await page.evaluate(state => localFixture.update({ ...state, tutorial: { step: 'drive', stage: 0, total: 5 } }), state);
        check(await page.locator('.local-race:not([hidden]) .local-track-status').isHidden(), 'Tutorial hides event');
        await page.evaluate(state => localFixture.update({ ...state, trackEvent: { phase: 'idle' } }), state);
        check(await page.locator('.local-race:not([hidden]) .local-track-status').isHidden(), 'Idle hides event');
      }
    }
    await page.evaluate(() => localFixture.destroy());
    await page.locator('#join-button').click();
    await page.waitForFunction(() => !document.querySelector('#hud').hidden);
    for (const [width, height] of sizes) {
      await page.setViewportSize({ width, height });
      for (const phase of ['warning', 'active', 'idle']) {
        await page.evaluate(({ phase, track }) => GnomHost.update(JSON.stringify({ status: 'racing', phase: 'racing', players: [], speed: 0, lap: 3, ping: 0, elapsed: 0, track, trackEvent: { phase, remaining: 2.1 } })), { phase, track });
        check(await page.locator('#track-status').isHidden() === (phase === 'idle'), 'Network phase visibility');
        if (phase !== 'idle') {
          check(await page.evaluate(() => {
            const status = document.querySelector('#track-status'), r = status.getBoundingClientRect();
            return document.querySelector('#hud').getBoundingClientRect().bottom <= r.top && status.scrollWidth <= status.clientWidth;
          }), `Network strip space ${width}x${height}`);
          check(await page.locator('#track-status').textContent() === (phase === 'warning' ? 'ТРАССА МЕНЯЕТСЯ · 3 с' : 'НОВЫЕ ПРЕПЯТСТВИЯ'), 'Network phase text');
          check(await page.evaluate(() => {
            const canvas = document.querySelector('#minimap');
            const pixels = canvas.getContext('2d').getImageData(0, 0, canvas.width, canvas.height).data;
            for (let i = 0; i < pixels.length; i += 4) if (pixels[i] === 100 && pixels[i + 1] === 227 && pixels[i + 2] === 219 && pixels[i + 3] > 0) return true;
            return false;
          }), 'Network minimap renders cyan shortcut');
        }
      }
    }
    check(errors.length === 0, JSON.stringify(errors));
    console.log(`TRACK_EVENT_HUD_PASS ${checks} checks`);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
