const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../..');
const output = process.env.GNOM_QA_OUT || '/tmp/gnom-hud-audit';
const track = JSON.parse(fs.readFileSync(path.join(root, 'shared/track-manifest.json'), 'utf8'));

(async () => {
  fs.mkdirSync(output, { recursive: true });
  const browser = await chromium.launch({ headless: true });
  const failures = [], errors = [];
  let checks = 0;
  const check = (condition, message) => { checks++; if (!condition) failures.push(message); };
  try {
    const page = await browser.newPage();
    page.on('pageerror', error => errors.push(error.message));
    await page.route('http://localhost/**', route => {
      const url = new URL(route.request().url());
      if (url.pathname === '/') return route.fulfill({ contentType: 'text/html', body: '<link rel="stylesheet" href="/local-race.css"><link rel="stylesheet" href="/control-settings.css"><style>body{margin:0;background:#55665d}button{box-sizing:border-box}</style>' });
      const file = path.join(root, 'web', url.pathname);
      if (fs.existsSync(file) && fs.statSync(file).isFile()) return route.fulfill({ path: file });
      return route.fulfill({ status: 404, body: '' });
    });
    await page.goto('http://localhost/');
    for (const file of ['track-map.js', 'control-settings.js', 'local-race.js']) await page.addScriptTag({ path: path.join(root, 'web', file) });
    await page.evaluate(() => { window.commands = []; window.ui = GnomLocalUI.create({ send: value => commands.push(value) }); });
    const effects = Object.fromEntries(['fanta', 'mermaid_rum', 'ice_rum', 'stroh80', 'lays_crab', 'burn', 'crystal_shield', 'weapon_guard'].map(key => [key, { remaining: 9.9 }]));
    const players = Array.from({ length: 10 }, (_, i) => ({ id: i + 1, rank: i + 1, name: 'ОченьДлинноеИмяСоперникаДляПроверкиГраниц', position: [0, 0] }));
    for (const [width, height] of [[1600, 900], [1280, 720], [844, 390], [390, 844]]) {
      await page.setViewportSize({ width, height });
      for (const count of [1, 2, 3, 4]) for (const layout of count === 2 ? ['side-by-side', 'stacked'] : ['side-by-side']) {
        const label = `${width}x${height}-${count}-${layout}`;
        const seats = Array.from({ length: count }, (_, index) => ({ id: index + 1, device: index - 1, styleId: 'handling', health: 100, lap: 3, rank: 10, elapsed: 180, speed: 999, reverse: true, shards: 20, effects, attackWarning: 'front', items: ['seeker', 'crystal_shield'], canUseItems: true, driftLevel: 3, driftSegments: [1, 1, 1], blurIntensity: index === 0 ? 1 : 0, driving: { start_boost_remaining: 1, slipstream_boost_remaining: 1 } }));
        const state = { seats, players, layout, phase: 'racing', trackDescriptor: track, trackEvent: { phase: 'warning', remaining: 2 } };
        await page.evaluate(state => ui.update(state), state);
        const geometry = await page.evaluate(() => {
          const problems = [];
          const overlap = (a, b) => Math.min(a.right, b.right) - Math.max(a.left, b.left) > 1 && Math.min(a.bottom, b.bottom) - Math.max(a.top, b.top) > 1;
          const pause = document.querySelector('.local-pause-button').getBoundingClientRect();
          const panes = [...document.querySelectorAll('.local-pane')];
          const stacked = document.querySelector('.local-grid').classList.contains('stacked');
          for (const pane of panes) {
            const bounds = pane.getBoundingClientRect(), seat = pane.dataset.seat;
            const columns = panes.length === 1 || (panes.length === 2 && stacked) ? 1 : 2;
            const rows = panes.length > 2 || (panes.length === 2 && stacked) ? 2 : 1;
            if (Math.abs(bounds.width - innerWidth / columns) > 1 || Math.abs(bounds.height - innerHeight / rows) > 1 || Math.abs(bounds.left - Number(seat) % columns * innerWidth / columns) > 1 || Math.abs(bounds.top - Math.floor(Number(seat) / columns) * innerHeight / rows) > 1) problems.push(`P${seat} camera sector mismatch`);
            const nodes = [...pane.querySelectorAll(':scope > div:not(.local-sector-blur):not(.local-countdown):not(.local-finish), :scope > canvas')].filter(node => { const r = node.getBoundingClientRect(); return r.width && r.height; });
            for (const node of nodes) {
              const r = node.getBoundingClientRect();
              if (r.left < bounds.left - 1 || r.right > bounds.right + 1 || r.top < bounds.top - 1 || r.bottom > bounds.bottom + 1) problems.push(`P${seat} outside ${node.className}`);
              if (!node.classList.contains('local-rank') && (node.scrollWidth > node.clientWidth + 1 || node.scrollHeight > node.clientHeight + 1)) problems.push(`P${seat} overflow ${node.className}`);
              if (overlap(pause, r)) problems.push(`P${seat} pause overlaps ${node.className}`);
            }
            for (let i = 0; i < nodes.length; i++) for (let j = i + 1; j < nodes.length; j++) if (overlap(nodes[i].getBoundingClientRect(), nodes[j].getBoundingClientRect())) problems.push(`P${seat} overlap ${nodes[i].className}/${nodes[j].className}`);
            const reverse = pane.querySelector('.local-reverse').getBoundingClientRect();
            for (const node of nodes.filter(node => !node.classList.contains('local-speed'))) if (overlap(reverse, node.getBoundingClientRect())) problems.push(`P${seat} overlap reverse/${node.className}`);
          }
          const overview = document.querySelector('.local-overview');
          if (overview) {
            const map = overview.querySelector('canvas').getBoundingClientRect(), p = overview.getBoundingClientRect();
            if (!map.width || !map.height || map.left < p.left || map.right > p.right || map.top < p.top || map.bottom > p.bottom) problems.push('overview map hidden or outside');
          }
          if (overview) for (const node of overview.querySelectorAll('h3,li')) {
            const r = node.getBoundingClientRect(), p = overview.getBoundingClientRect();
            if (r.left < p.left || r.right > p.right || r.top < p.top || r.bottom > p.bottom) problems.push(`overview outside ${node.tagName}`);
            const status = document.querySelector('.local-track-status');
            if (!status.hidden && overlap(r, status.getBoundingClientRect())) problems.push(`overview track status overlaps ${node.tagName}`);
          }
          return problems;
        });
        check(!geometry.length, `${label}: ${geometry.join('; ')}`);
        await page.screenshot({ path: path.join(output, `${label}.png`) });
        const blurs = await page.locator('.local-sector-blur').evaluateAll(nodes => nodes.map(node => node.style.backdropFilter));
        check(blurs[0] === 'blur(3px)' && blurs.slice(1).every(value => value === 'blur(0px)'), `${label}: blur isolation`);
        check(await page.locator('.local-slot img').evaluateAll(nodes => nodes.every(node => node.complete && node.naturalWidth > 0)), `${label}: item art renders`);
        check(await page.locator('.local-effect').evaluateAll(nodes => nodes.length > 0 && nodes.every(node => node.title && node.getAttribute('aria-label') === node.title && node.querySelector('img')?.naturalWidth > 0)), `${label}: compact effects retain names and art`);
        await page.evaluate(state => ui.update({ ...state, graphics: { reducedEffects: true } }), state);
        check(await page.locator('.local-sector-blur').first().evaluate(node => node.style.backdropFilter === 'blur(0.6px)'), `${label}: reduced effects preserved`);
        await page.locator('.local-slot').nth((count - 1) * 2 + 1).click();
        check(await page.evaluate(count => { const command = commands.at(-1); return command.type === 'local_use_item' && command.seat === count - 1 && command.slot === 1; }, count), `${label}: item routed to seat`);
        await page.evaluate(state => ui.update({ ...state, countdown: 3, seats: state.seats.map(seat => ({ ...seat, canUseItems: false, effects: {}, attackWarning: '' })) }), state);
        check(await page.locator('.local-slot:disabled').count() === count * 2 && await page.locator('.local-countdown').first().textContent() === '3', `${label}: countdown blocks items`);
        await page.evaluate(state => ui.update({ ...state, phase: 'results', seats: state.seats.map(seat => ({ ...seat, finished: true, canUseItems: false, dnf: seat.id === 1 })) }), state);
        check(await page.locator('.local-finish:not([hidden])').count() === count, `${label}: results for all seats`);
        check(await page.locator('.local-finish').first().locator('strong').textContent() === 'DNF', `${label}: DNF`);
        check(await page.locator('.local-finish').evaluateAll(nodes => nodes.every(node => {
          const r = node.getBoundingClientRect(), p = node.parentElement.getBoundingClientRect();
          return r.left >= p.left && r.right <= p.right && r.top >= p.top && r.bottom <= p.bottom && node.scrollWidth <= node.clientWidth + 1 && [...node.children].every(child => { const c = child.getBoundingClientRect(); return c.left >= r.left && c.right <= r.right && c.top >= r.top && c.bottom <= r.bottom; });
        })), `${label}: results fit own sector`);
        await page.screenshot({ path: path.join(output, `${label}-results.png`) });
        await page.locator('.local-finish .local-button').last().click();
        check(await page.evaluate(count => { const command = commands.at(-1); return command.type === 'local_ready' && command.seat === count - 1; }, count), `${label}: rematch readiness routed`);
        await page.evaluate(state => ui.update({ ...state, phase: 'results', seats: state.seats.map(seat => ({ ...seat, finished: true, ready: true })) }), state);
        check(await page.locator('.local-finish button:disabled').count() === count, `${label}: ready cannot repeat`);
        await page.evaluate(state => ui.update({ ...state, trackEvent: { phase: 'idle' }, seats: state.seats.map(seat => ({ ...seat, effects: {}, attackWarning: '', health: 0, destroyedRemaining: 2, invulnerableRemaining: 1, items: ['', ''], canUseItems: false })) }), state);
        check(await page.locator('.local-slot:disabled').count() === count * 2 && await page.locator('.local-health progress.critical').count() === count, `${label}: destruction empty inventory and critical health`);
        check(await page.locator('.local-effect.recovery').count() === count && await page.locator('.local-effect.invulnerable').count() === count, `${label}: recovery and protection visible`);
        await page.evaluate(state => ui.update({ ...state, seats: state.seats.map(seat => ({ ...seat, driving: { slipstream_charge: .63 } })) }), state);
        check(await page.locator('.local-effect.slipstream b').evaluateAll(nodes => nodes.length > 0 && nodes.every(node => node.textContent === '63%' && node.getBoundingClientRect().width > 0)), `${label}: slipstream charge preserved`);
      }
    }
    check(errors.length === 0, `Browser errors: ${errors.join('; ')}`);
    fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify({ checks, failures }, null, 2));
    console.log(JSON.stringify({ checks, failures }, null, 2));
    assert.equal(failures.length, 0, 'Local HUD audit failures');
    console.log(`LOCAL_HUD_PASS ${checks} checks`);
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
