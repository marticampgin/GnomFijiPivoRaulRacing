import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createHmac, randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as delay } from 'node:timers/promises';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const manifest = JSON.parse(readFileSync(resolve(root, 'shared/track-manifest.json'), 'utf8'));
const { track_id, schema_version, simulation_revision, simulation_hash, art_revision } = manifest;
const compatibility = { protocol_version: 8, vehicle_state_version: 1, loadout_hash: 'prototype-v11', track: { track_id, schema_version, simulation_revision, simulation_hash, art_revision } };
const secret = 'network-probe-only-not-a-deployment-secret-2026';
const port = Number(process.env.NETWORK_TEST_PORT || 19080);
const url = `ws://127.0.0.1:${port}`;
const peers = [];
let output = '';
let checks = 0;
const worker = spawn(process.env.GODOT_BIN || 'godot', ['--headless', '--path', resolve(root, 'game'), '--', '--race-worker'], {
  cwd: root,
  env: { ...process.env, RACE_TICKET_SECRET: secret, RACE_PORT: String(port) },
  stdio: ['ignore', 'pipe', 'pipe'],
});
worker.stdout.on('data', value => { output += value; });
worker.stderr.on('data', value => { output += value; });
worker.on('error', error => { output += error.message; });

function ticket(id, changes = {}) {
  const payload = Buffer.from(JSON.stringify({ v: 3, ...compatibility, style_id: 'handling', match_id: 'prototype-1', expires_at: Math.floor(Date.now() / 1000) + 60, player_id: id, display_name: `Probe ${id}`, jti: randomUUID(), ...changes })).toString('base64url');
  return `${payload}.${createHmac('sha256', secret).update(payload).digest('base64url')}`;
}

async function waitFor(predicate, label, timeout = 5000) {
  const deadline = Date.now() + timeout;
  while (Date.now() < deadline) {
    const result = predicate();
    if (result) return result;
    await delay(10);
  }
  throw new Error(`Timed out: ${label}\n${output}`);
}

async function connect(signedTicket, descriptor = compatibility) {
  const socket = new WebSocket(url);
  const peer = { socket, messages: [], closed: false, reason: '', code: null };
  peers.push(peer);
  socket.addEventListener('message', event => {
    peer.messages.push(JSON.parse(event.data));
    if (peer.messages.length > 500) peer.messages.shift();
  });
  socket.addEventListener('close', event => { peer.closed = true; peer.reason = event.reason; peer.code = event.code; });
  socket.addEventListener('error', () => {});
  await waitFor(() => socket.readyState === WebSocket.OPEN, 'socket open');
  if (signedTicket !== undefined) socket.send(JSON.stringify({ type: 'join', ticket: signedTicket, compatibility: descriptor }));
  return peer;
}

function verify(condition, label) {
  assert.ok(condition, label);
  checks++;
  console.log(`PASS ${label}`);
}

async function rejectTicket(value, label) {
  const peer = await connect(value);
  await waitFor(() => peer.closed, label);
  verify(peer.reason === 'invalid_ticket', label);
}

async function joined(id, value = ticket(id)) {
  const peer = await connect(value);
  const welcome = await waitFor(() => peer.messages.find(message => message.type === 'welcome'), `welcome ${id}`);
  verify(welcome.player_id === id, `authoritative identity ${id}`);
  assert.deepEqual(welcome.compatibility, compatibility, 'worker welcome binds authoritative simulation');
  peer.ack = welcome.ack;
  return peer;
}

function ownState(peer, id, predicate = () => true) {
  return peer.messages.filter(message => message.type === 'snapshot').reverse().flatMap(message => message.players).find(player => player.id === id && predicate(player));
}

try {
  await waitFor(() => output.includes('RACE_WORKER_READY'), 'worker ready', 30000);
  const goodTicket = ticket('driver-a');
  const [payload, signature] = goodTicket.split('.');
  await rejectTicket(`${payload}.${signature.startsWith('A') ? 'B' : 'A'}${signature.slice(1)}`, 'tampered signature rejected');
  await rejectTicket(ticket('expired', { expires_at: Math.floor(Date.now() / 1000) - 1 }), 'expired ticket rejected');
  await rejectTicket(ticket('wrong-match', { match_id: 'other' }), 'wrong match rejected');
  await rejectTicket(ticket('old-protocol', { protocol_version: 1 }), 'signed stale wire protocol rejected');
  await rejectTicket(ticket('previous-protocol', { protocol_version: 2 }), 'pre-lifecycle wire protocol rejected');
  await rejectTicket(ticket('pre-styles', { protocol_version: 3 }), 'pre-style wire protocol rejected');
  await rejectTicket(ticket('pre-items', { protocol_version: 4 }), 'pre-item wire protocol rejected');
  await rejectTicket(ticket('pre-item-balance', { loadout_hash: 'prototype-v6' }), 'pre-item balance rejected');
  await rejectTicket(ticket('pre-reverse-balance', { loadout_hash: 'prototype-v7' }), 'pre-reverse balance rejected');
  await rejectTicket(ticket('pre-shards-balance', { loadout_hash: 'prototype-v8' }), 'pre-shards balance rejected');
  await rejectTicket(ticket('pre-shards-wire', { protocol_version: 5 }), 'pre-shards wire rejected');
  await rejectTicket(ticket('pre-counterplay-balance', { loadout_hash: 'prototype-v9' }), 'pre-counterplay balance rejected');
  await rejectTicket(ticket('pre-counterplay-wire', { protocol_version: 6 }), 'pre-counterplay wire rejected');
  await rejectTicket(ticket('pre-track-event-balance', { loadout_hash: 'prototype-v10' }), 'pre-track-event balance rejected');
  await rejectTicket(ticket('pre-track-event-wire', { protocol_version: 7 }), 'pre-track-event wire rejected');
  await rejectTicket(ticket('bad-style', { style_id: 'faster' }), 'unknown signed style rejected');
  await rejectTicket(ticket('missing-style', { style_id: undefined }), 'missing signed style rejected');
  await rejectTicket(ticket('bot:1'), 'reserved bot identity rejected');
  await rejectTicket(ticket('wrong-state', { vehicle_state_version: 999 }), 'signed unsupported vehicle state schema rejected');
  await rejectTicket(ticket('old-vehicle', { loadout_hash: 'prototype-v1' }), 'signed old vehicle simulation rejected');
  await rejectTicket(ticket('sharp-box-vehicle', { loadout_hash: 'prototype-v2' }), 'signed sharp-box vehicle simulation rejected');
  await rejectTicket(ticket('no-contact-vehicle', { loadout_hash: 'prototype-v3' }), 'signed pre-contact vehicle simulation rejected');
  await rejectTicket(ticket('narrow-contact-vehicle', { loadout_hash: 'prototype-v4' }), 'signed narrow contact envelope rejected');
  await rejectTicket(ticket('wrong-track', { track: { ...compatibility.track, simulation_hash: 'a'.repeat(64) } }), 'signed stale track hash rejected');
  for (const [label, descriptor] of [
    ['stale hello protocol', { ...compatibility, protocol_version: 1 }],
    ['pre-item hello protocol', { ...compatibility, protocol_version: 4 }],
    ['pre-item hello balance', { ...compatibility, loadout_hash: 'prototype-v6' }],
    ['pre-reverse hello balance', { ...compatibility, loadout_hash: 'prototype-v7' }],
    ['pre-shards hello balance', { ...compatibility, loadout_hash: 'prototype-v8' }],
    ['pre-shards hello wire', { ...compatibility, protocol_version: 5 }],
    ['pre-counterplay hello balance', { ...compatibility, loadout_hash: 'prototype-v9' }],
    ['pre-counterplay hello wire', { ...compatibility, protocol_version: 6 }],
    ['pre-track-event hello balance', { ...compatibility, loadout_hash: 'prototype-v10' }],
    ['pre-track-event hello wire', { ...compatibility, protocol_version: 7 }],
    ['unsupported hello state schema', { ...compatibility, vehicle_state_version: 999 }],
    ['old hello vehicle simulation', { ...compatibility, loadout_hash: 'prototype-v1' }],
    ['sharp-box hello vehicle simulation', { ...compatibility, loadout_hash: 'prototype-v2' }],
    ['pre-contact hello simulation', { ...compatibility, loadout_hash: 'prototype-v3' }],
    ['narrow contact envelope', { ...compatibility, loadout_hash: 'prototype-v4' }],
    ['stale hello track', { ...compatibility, track: { ...compatibility.track, simulation_hash: 'a'.repeat(64) } }],
  ]) {
    const peer = await connect(ticket('incompatible-client'), descriptor);
    await waitFor(() => peer.closed, `${label} close`);
    verify(peer.reason === 'update_required' && !peer.messages.some(message => message.type === 'welcome'), `${label} rejected before racer admission`);
  }
  const first = await joined('driver-a', goodTicket);
  await rejectTicket(goodTicket, 'ticket replay rejected');
  const second = await joined('driver-b');
  const grid = await waitFor(() => first.messages.find(message => message.type === 'snapshot' && message.players.length === 10 && message.players.filter(player => !player.is_bot).length === 2), 'two humans and eight bots');
  verify(true, 'two real WebSocket clients share authoritative snapshot');
  verify(grid.track_event?.phase === 'idle' && grid.track_event.trigger_tick === 0 && grid.track_event.active.length === 2 && grid.track_event.active.every(value => value === false), 'snapshot includes explicit authoritative initial track event');
  verify(new Set(grid.players.map(player => player.slot)).size === 10, 'ten racers have distinct grid slots');
  verify(new Set(grid.players.filter(player => player.is_bot).map(player => player.style_id)).size === 4, 'bots use all four authoritative styles');
  verify(grid.players.every(player => player.combat && player.combat.health === player.combat.max_health
    && player.combat.slots.length === 2 && player.combat.item_ack === 0), 'every racer starts with authoritative durability and two slots');
  await waitFor(() => first.messages.find(message => message.type === 'snapshot' && message.countdown === 0), 'countdown complete', 8000);
  const initialItemState = ownState(first, 'driver-a');
  const itemCommand = { type: 'use_item', sequence: 1, race_id: grid.race_id, epoch: initialItemState.epoch, slot: 0 };
  first.socket.send(JSON.stringify(itemCommand));
  const acknowledgedItem = await waitFor(() => ownState(first, 'driver-a', player => player.combat.item_ack === 1), 'empty-slot item command acknowledged');
  first.socket.send(JSON.stringify(itemCommand));
  await delay(120);
  verify(!first.closed && ownState(first, 'driver-a').combat.item_ack === 1, 'duplicate item command is idempotent without disconnect');
  assert.deepEqual(ownState(first, 'driver-a').combat.slots, acknowledgedItem.combat.slots);
  verify(true, 'duplicate item command leaves inventory unchanged');
  first.socket.send(JSON.stringify({ ...itemCommand, sequence: 2, race_id: grid.race_id + 1 }));
  first.socket.send(JSON.stringify({ ...itemCommand, sequence: 2, epoch: initialItemState.epoch + 1 }));
  await delay(120);
  verify(!first.closed && ownState(first, 'driver-a').combat.item_ack === 1, 'wrong race and recovery epoch cannot advance item acknowledgement');
  assert.deepEqual(ownState(first, 'driver-a').combat.slots, acknowledgedItem.combat.slots);
  verify(true, 'stale item commands do not consume or grant inventory');
  const before = ownState(first, 'driver-a').state.position;
  let sequence = first.ack;
  for (let index = 0; index < 60; index++) {
    first.socket.send(JSON.stringify({ type: 'input', sequence: ++sequence, steering: 0, throttle: 1, brake: 0, drift: false }));
    await delay(1000 / 60);
  }
  const driven = await waitFor(() => ownState(first, 'driver-a', player => player.ack >= sequence), 'input acknowledgement');
  verify(Math.hypot(...driven.state.position.map((value, index) => value - before[index])) > 3, 'server advances car from validated input');
  const bot = grid.players.find(player => player.is_bot);
  const movingBot = ownState(first, bot.id);
  verify(Math.hypot(...movingBot.state.position.map((value, index) => value - bot.state.position[index])) > 3, 'server bot drives under authoritative physics');
  await delay(1300);
  // Braking does not cancel legitimate rear impacts from bots passing the idle car.
  const stopped = await waitFor(() => {
    const latest = ownState(first, 'driver-a');
    return Math.hypot(latest.state.velocity[0], latest.state.velocity[2]) < 0.5 ? latest : null;
  }, 'stale-input braking after contact traffic settles', 10000);
  verify(true, 'stale input brakes authoritative car after external pushes settle');
  first.socket.close();
  await waitFor(() => first.closed, 'disconnect');
  const resumed = await joined('driver-a', ticket('driver-a', { style_id: 'drift' }));
  verify(resumed.ack === sequence, 'new signed ticket reconnects with acknowledged sequence');
  const resumedState = await waitFor(() => ownState(resumed, 'driver-a'), 'resumed snapshot');
  verify(resumedState.style_id === 'handling' && resumedState.next_style_id === 'drift', 'reconnect locks current style and queues next race style');
  verify(Math.hypot(...resumedState.state.position.map((value, index) => value - stopped.state.position[index])) < 0.5, 'reconnect preserves server position');
  resumed.socket.send(JSON.stringify({ type: 'input', sequence, steering: 0, throttle: 1, brake: 0, drift: false }));
  await waitFor(() => resumed.closed, 'sequence replay close');
  verify(resumed.reason === 'invalid_input', 'replayed input sequence rejected');
  const malformed = await joined('driver-a');
  malformed.socket.send(JSON.stringify({ type: 'input', sequence: sequence + 1, steering: null, throttle: 1, brake: 0, drift: false }));
  await waitFor(() => malformed.closed, 'non-numeric input close');
  verify(malformed.reason === 'invalid_input', 'non-numeric input rejected over socket');
  for (const mutation of [{ slot: 2 }, { sequence: 1.5 }, { extra: true }, { epoch: null }, { sequence: 122 }]) {
    const malformedItem = await joined('driver-a');
    const itemState = await waitFor(() => ownState(malformedItem, 'driver-a'), 'item validation snapshot');
    malformedItem.socket.send(JSON.stringify({ type: 'use_item', sequence: itemState.combat.item_ack + 1,
      race_id: grid.race_id, epoch: itemState.epoch, slot: 0, ...mutation }));
    await waitFor(() => malformedItem.closed, 'malformed item close');
    verify(malformedItem.reason === 'invalid_item', `malformed item rejected: ${JSON.stringify(mutation)}`);
  }
  const unknown = await joined('driver-a');
  unknown.socket.send(JSON.stringify({ type: 'grant_money', amount: 1000 }));
  await waitFor(() => unknown.closed, 'unknown packet close');
  verify(unknown.reason === 'unknown_packet', 'unknown packet cannot mutate economy or simulation');
  const flooding = await joined('driver-a');
  for (let index = 0; index < 110; index++) flooding.socket.send(JSON.stringify({ type: 'ping', sent: index }));
  await waitFor(() => flooding.closed, 'flood close');
  verify(flooding.reason === 'rate_limit', 'packet rate limit enforced');
  for (let index = 2; index < 10; index++) {
    const late = await joined(`slot-${index}`);
    const waiting = await waitFor(() => ownState(late, `slot-${index}`), 'late join state');
    verify(waiting.spectator === true && waiting.position === 0 && !waiting.finished, 'late human waits without inheriting bot progress');
  }
  const overflow = await connect(ticket('eleventh'));
  await waitFor(() => overflow.closed, 'lobby capacity');
  verify(overflow.reason === 'lobby_full', 'ten-car cap includes reserved reconnect slots');
  verify(!output.includes('SCRIPT ERROR'), 'worker has no GDScript runtime errors');
  console.log(`NETWORK_INTEGRATION_PROBE ${checks}/${checks} passed`);
} catch (error) {
  console.error(error);
  process.exitCode = 1;
} finally {
  for (const peer of peers) peer.socket.close();
  const exited = new Promise(resolveExit => worker.once('exit', resolveExit));
  worker.kill('SIGTERM');
  await Promise.race([exited, delay(2000)]);
  if (worker.exitCode === null && worker.signalCode === null) worker.kill('SIGKILL');
}
