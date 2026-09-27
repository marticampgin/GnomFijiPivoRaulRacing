const { chromium } = require('playwright');
const fs = require('node:fs/promises');
const assert = require('node:assert/strict');

const url = process.env.GNOM_NETWORK_URL || 'http://127.0.0.1:8787/';
const out = process.env.GNOM_NETWORK_OUT || '/tmp/gnom-network-input';

(async () => {
  const target = new URL(url);
  assert.ok(target.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(target.hostname), 'Local preview only');
  await fs.mkdir(out, { recursive: true });
  const browser = await chromium.launch({ headless: process.env.GNOM_NETWORK_HEADLESS === '1' });
  const page = await browser.newPage({ viewport: { width: 1600, height: 900 } });
  const errors = [];
  const report = { passed: false, scenario: 'One ordered 650 ms outbound input stall, then keyboard movement; no physical gamepad acceptance.', browser: browser.version(), errors };
  page.on('pageerror', error => errors.push(error.message));
  await page.addInitScript(() => {
    const NativeSocket = window.WebSocket;
    const stats = window.networkInputQA = { inputs: 0, ack: 0, highestSequence: 0, maxUnacknowledged: 0, buffered: 0, flushed: 0, snapshots: 0, closes: [], stallStarted: false, stallComplete: false };
    window.WebSocket = class extends NativeSocket {
      constructor(...args) {
        super(...args);
        let playerId = null;
        let buffering = false;
        let stalled = false;
        const queue = [];
        this.addEventListener('message', event => {
          try {
            const packet = JSON.parse(event.data);
            if (packet.type === 'welcome') { playerId = packet.player_id; stats.ack = packet.ack; }
            if (packet.type === 'snapshot') {
              stats.snapshots++;
              const player = packet.players.find(entry => entry.id === playerId);
              if (player) stats.ack = player.ack;
            }
          } catch { /* No raw frames, identities or tickets are retained. */ }
        });
        this.addEventListener('close', event => stats.closes.push({ code: event.code, reason: event.reason }));
        this.send = data => {
          let packet;
          try { packet = JSON.parse(typeof data === 'string' ? data : new TextDecoder().decode(data)); } catch { return super.send(data); }
          if (packet.type !== 'input') return super.send(data);
          stats.inputs++;
          stats.highestSequence = Math.max(stats.highestSequence, packet.sequence);
          stats.maxUnacknowledged = Math.max(stats.maxUnacknowledged, packet.sequence - stats.ack);
          if (!stalled) {
            stalled = buffering = true;
            stats.stallStarted = true;
            setTimeout(() => {
              buffering = false;
              if (this.readyState === NativeSocket.OPEN) {
                for (const frame of queue) { super.send(frame); stats.flushed++; }
              }
              queue.length = 0;
              stats.stallComplete = true;
            }, 650);
          }
          if (buffering) { queue.push(data); stats.buffered++; return; }
          return super.send(data);
        };
      }
    };
  });
  const started = Date.now();
  try {
    await page.goto(url);
    await page.waitForFunction(() => !document.querySelector('#join-button')?.disabled, undefined, { timeout: 90000 });
    await page.locator('#profile-button').click();
    await page.locator('#profile-list button').first().click();
    await page.getByText('Вход выполнен', { exact: true }).waitFor();
    await page.locator('#profile-dialog .close-dialog').click();
    await page.locator('#join-button').click();
    await page.waitForFunction(() => window.networkInputQA.stallComplete, undefined, { timeout: 15000 });
    await page.waitForTimeout(1000);
    report.network = await page.evaluate(() => window.networkInputQA);
    assert.deepEqual(report.network.closes, [], 'Input burst disconnected the socket');
    assert.ok(report.network.buffered > 0 && report.network.flushed === report.network.buffered, 'Ordered input stall was not exercised');
    await page.waitForFunction(() => window.GnomHost.state?.status === 'racing' && window.GnomHost.state?.phase === 'racing', undefined, { timeout: 12000 });
    const before = await page.evaluate(() => ({ position: window.GnomHost.state.worldPosition, ack: window.networkInputQA.ack }));
    await page.keyboard.down('Space');
    await page.waitForFunction(() => window.GnomHost.state.speed > 15, undefined, { timeout: 7000 });
    await page.keyboard.up('Space');
    const after = await page.evaluate(() => ({ position: window.GnomHost.state.worldPosition, ack: window.networkInputQA.ack, status: window.GnomHost.state.status }));
    assert.ok(after.ack > before.ack, 'Acknowledgements did not resume');
    assert.ok(Math.hypot(...after.position.map((value, index) => value - before.position[index])) > 0.5, 'Kart did not move');
    report.movement = { acknowledgementDelta: after.ack - before.ack, distance: Math.hypot(...after.position.map((value, index) => value - before.position[index])) };
    report.network = await page.evaluate(() => window.networkInputQA);
    assert.ok(report.network.maxUnacknowledged <= 24, 'Client exceeded its 24-input transmission window');
    assert.equal(after.status, 'racing');
    assert.deepEqual(report.network.closes, []);
    assert.deepEqual(errors, []);
    await page.screenshot({ path: `${out}/network-input.png` });
    report.passed = true;
  } catch (error) {
    report.error = error.message;
    report.network = await page.evaluate(() => window.networkInputQA).catch(() => null);
    await page.screenshot({ path: `${out}/failure.png` }).catch(() => {});
    process.exitCode = 1;
  } finally {
    report.elapsedSeconds = (Date.now() - started) / 1000;
    await fs.writeFile(`${out}/result.json`, JSON.stringify(report, null, 2));
    await browser.close();
    console.log(JSON.stringify(report, null, 2));
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
