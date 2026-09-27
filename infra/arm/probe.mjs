import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { performance, monitorEventLoopDelay } from 'node:perf_hooks';
import { setTimeout as delay } from 'node:timers/promises';
import { parseArgs } from 'node:util';

export function percentile(values, fraction) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return Number(sorted[Math.min(sorted.length - 1, Math.max(0, Math.ceil(fraction * sorted.length) - 1))].toFixed(3));
}

export function loopbackOrigin(value) {
  const origin = new URL(value);
  if (origin.protocol !== 'http:' || !['127.0.0.1', 'localhost', '[::1]'].includes(origin.hostname) || origin.origin !== value) throw new Error('Probe only accepts an exact loopback HTTP origin');
  return origin.origin;
}

export function routeFor(descriptor) {
  const route = descriptor?.minimap?.polyline;
  if (!Array.isArray(route) || route.length < 4 || route.length > 4096
    || !route.every(point => Array.isArray(point) && point.length === 2 && point.every(Number.isFinite))
    || Math.hypot(route[0][0] - route.at(-1)[0], route[0][1] - route.at(-1)[1]) > 0.01) throw new Error('Load probe requires a valid closed track descriptor');
  if (route.slice(1).some((point, index) => Math.hypot(point[0] - route[index][0], point[1] - route[index][1]) < 0.00001)) throw new Error('Load probe rejects zero-length route segments');
  return route;
}

export function steeringFor(state, route) {
  if (!state) return 0;
  if (!Array.isArray(route) || route.length < 4) throw new Error('Load probe has no route');
  const [x, , z] = state.position;
  let segment = 0, fraction = 0, distance = Infinity;
  for (let index = 0; index < route.length - 1; index++) {
    const [ax, az] = route[index], [bx, bz] = route[index + 1];
    const dx = bx - ax, dz = bz - az;
    const t = Math.max(0, Math.min(1, ((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz)));
    const candidate = Math.hypot(x - ax - dx * t, z - az - dz * t);
    if (candidate < distance) { segment = index; fraction = t; distance = candidate; }
  }
  // This is only a deterministic load-fixture driver, not the game's bot AI.
  let lookAhead = 12;
  let target;
  for (let step = 0; step < route.length; step++) {
    const [ax, az] = route[segment], [bx, bz] = route[segment + 1];
    const length = Math.hypot(bx - ax, bz - az);
    if (lookAhead <= length * (1 - fraction)) {
      const t = fraction + lookAhead / length;
      target = [ax + (bx - ax) * t, az + (bz - az) * t];
      break;
    }
    lookAhead -= length * (1 - fraction);
    segment = (segment + 1) % (route.length - 1);
    fraction = 0;
  }
  if (!target) target = route[segment];
  const dx = target[0] - x, dz = target[1] - z;
  const fx = -state.basis[2][0], fz = -state.basis[2][2];
  const turn = Math.atan2(fz * dx - fx * dz, fx * dx + fz * dz);
  return Math.max(-1, Math.min(1, -turn * 2.2));
}

const summary = values => ({ count: values.length, p50: percentile(values, 0.5), p95: percentile(values, 0.95), p99: percentile(values, 0.99) });

async function run() {
  const { values } = parseArgs({ options: { origin: { type: 'string', default: 'http://127.0.0.1:8787' }, seconds: { type: 'string', default: '30' }, players: { type: 'string', default: '2' }, expect: { type: 'string', default: 'test' }, out: { type: 'string' } } });
  const origin = loopbackOrigin(values.origin);
  const seconds = Number(values.seconds), count = Number(values.players);
  if (!Number.isInteger(seconds) || seconds < 10 || seconds > 3600 || !Number.isInteger(count) || count < 1 || count > 10) throw new Error('Use 10..3600 seconds and 1..10 players');
  if (!['test', 'local'].includes(values.expect)) throw new Error('Only local/test environment probes are permitted');
  const health = await fetch(`${origin}/api/health`, { signal: AbortSignal.timeout(5000) });
  if (!health.ok || (await health.json()).environment !== values.expect) throw new Error('Unexpected API environment; refusing to send load');
  const peers = [], intervals = [], errors = [], snapshotIntervals = [], pingRtt = [], ackLatency = [];
  const loop = monitorEventLoopDelay({ resolution: 10 });
  const startedAt = new Date().toISOString();
  const started = performance.now();
  const warmupUntil = started + 5000;
  let deliberateShutdown = false;
  let inputTimer;
  loop.enable();
  try {
    for (let index = 0; index < count; index++) {
      const bootstrap = await fetch(`${origin}/api/auth/bootstrap`, { headers: { Origin: origin }, signal: AbortSignal.timeout(5000) });
      if (!bootstrap.ok) throw new Error(`Bootstrap rejected: ${bootstrap.status}`);
      const cookie = bootstrap.headers.getSetCookie()[0]?.split(';')[0];
      const session = await bootstrap.json();
      if (!cookie || !session.csrfToken) throw new Error('Fresh guest session missing');
      const response = await fetch(`${origin}/api/race/ticket`, { method: 'POST', headers: { Origin: origin, Cookie: cookie, 'X-CSRF-Token': session.csrfToken, 'Content-Type': 'application/json' }, body: '{}', signal: AbortSignal.timeout(5000) });
      if (!response.ok) throw new Error(`Ticket rejected: ${response.status}`);
      const join = await response.json();
      const route = routeFor(join.track);
      const socketUrl = new URL(join.websocketUrl);
      if (socketUrl.protocol !== 'ws:' || !['127.0.0.1', 'localhost', '[::1]'].includes(socketUrl.hostname)) throw new Error('Refusing non-loopback race URL');
      const socket = new WebSocket(socketUrl);
      const peer = { socket, route, id: join.playerId, sequence: 0, state: null, sent: new Map(), lastSnapshot: null, firstTick: null, lastTick: null, firstAt: null, lastAt: null, welcome: false, distance: 0, lastPosition: null, restarts: 0, lastRestart: 0, snapshots: 0 };
      peers.push(peer);
      socket.addEventListener('open', () => socket.send(JSON.stringify({ type: 'join', ticket: join.ticket, compatibility: join.compatibility })));
      socket.addEventListener('error', () => errors.push(`peer ${index}: socket error`));
      socket.addEventListener('close', event => { if (!deliberateShutdown) errors.push(`peer ${index}: closed ${event.code} ${event.reason}`); });
      socket.addEventListener('message', event => {
        const packet = JSON.parse(event.data);
        const now = performance.now();
        if (packet.type === 'welcome') { peer.welcome = true; peer.sequence = packet.ack; return; }
        if (packet.type === 'pong') { if (now >= warmupUntil) pingRtt.push(now - packet.sent); return; }
        if (packet.type !== 'snapshot') return;
        const own = packet.players.find(player => player.id === peer.id);
        if (!own) return;
        peer.state = own.state;
        peer.snapshots++;
        if (peer.lastPosition) peer.distance += Math.hypot(...own.state.position.map((value, coordinate) => value - peer.lastPosition[coordinate]));
        peer.lastPosition = own.state.position;
        if (now >= warmupUntil) {
          if (peer.lastSnapshot !== null) snapshotIntervals.push(now - peer.lastSnapshot);
          peer.lastSnapshot = now;
          if (peer.firstTick === null) { peer.firstTick = packet.tick; peer.firstAt = now; }
          peer.lastTick = packet.tick;
          peer.lastAt = now;
          if (peer.sent.has(own.ack)) ackLatency.push(now - peer.sent.get(own.ack));
        }
        for (const sequence of peer.sent.keys()) if (sequence <= own.ack) peer.sent.delete(sequence);
        if (own.finished && now - peer.lastRestart > 1500) {
          socket.send(JSON.stringify({ type: 'restart' }));
          peer.lastRestart = now;
          peer.restarts++;
        }
      });
      const deadline = performance.now() + 5000;
      while (!peer.welcome && performance.now() < deadline && !errors.length) await delay(10);
      if (!peer.welcome) throw new Error(`Peer ${index} did not join`);
    }
    let nextInputAt = performance.now();
    const sendInputs = () => {
      const now = performance.now();
      for (const peer of peers) {
        if (peer.socket.readyState !== WebSocket.OPEN) continue;
        if (peer.socket.bufferedAmount > 65536 || peer.sent.size >= 120) { errors.push('Load generator input backlog'); peer.socket.close(); continue; }
        peer.sent.set(++peer.sequence, now);
        peer.socket.send(JSON.stringify({ type: 'input', sequence: peer.sequence, steering: steeringFor(peer.state, peer.route), throttle: 1, brake: 0, drift: false }));
      }
      nextInputAt += 1000 / 60;
      if (nextInputAt < now - 1000 / 30) nextInputAt = now + 1000 / 60;
      inputTimer = setTimeout(sendInputs, Math.max(1, Math.ceil(nextInputAt - performance.now())));
    };
    sendInputs();
    intervals.push(setInterval(() => {
      for (const peer of peers) if (peer.socket.readyState === WebSocket.OPEN) peer.socket.send(JSON.stringify({ type: 'ping', sent: performance.now() }));
    }, 1000));
    const until = performance.now() + seconds * 1000;
    while (performance.now() < until && !errors.length) await delay(100);
  } finally {
    deliberateShutdown = true;
    clearTimeout(inputTimer);
    for (const interval of intervals) clearInterval(interval);
    for (const peer of peers) peer.socket.close();
    loop.disable();
  }
  const report = {
    schemaVersion: 1, startedAt, environment: values.expect, players: peers.length, requestedSeconds: seconds, elapsedSeconds: (performance.now() - started) / 1000,
    scope: 'One local prototype worker, no car collisions/items/bots/production transport; not an ARM capacity result',
    snapshotArrivalIntervalMs: summary(snapshotIntervals), pingRoundTripMs: summary(pingRtt), inputAckRoundTripMs: summary(ackLatency),
    loadGeneratorEventLoopP99Ms: Number((loop.percentile(99) / 1e6).toFixed(3)),
    observedServerTicksPerSecond: peers.map(peer => peer.firstTick === null || peer.lastAt <= peer.firstAt ? null : Number(((peer.lastTick - peer.firstTick) * 1000 / (peer.lastAt - peer.firstAt)).toFixed(3))),
    distancesMeters: peers.map(peer => Number(peer.distance.toFixed(3))), snapshots: peers.map(peer => peer.snapshots), restarts: peers.map(peer => peer.restarts),
    physicsComputationDurationMs: null, physicsInstrumentationRequired: true,
    errors,
  };
  if (peers.some(peer => peer.distance < 1 || peer.snapshots < 10)) report.errors.push('Functional smoke failed: missing movement/snapshots');
  const output = resolve(values.out ?? `infra/arm/results/probe-${Date.now()}.json`);
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify({ report: output, errors: report.errors, players: peers.length, snapshotArrivalP99Ms: report.snapshotArrivalIntervalMs.p99 }, null, 2));
  if (report.errors.length) process.exitCode = 1;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  run().catch(error => { console.error(error.message); process.exitCode = 1; });
}
