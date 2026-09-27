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
const compatibility = { protocol_version: 2, vehicle_state_version: 1, loadout_hash: 'prototype-v3', track: { track_id, schema_version, simulation_revision, simulation_hash, art_revision } };
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
  const payload = Buffer.from(JSON.stringify({ v: 2, ...compatibility, match_id: 'prototype-1', expires_at: Math.floor(Date.now() / 1000) + 60, player_id: id, display_name: `Probe ${id}`, jti: randomUUID(), ...changes })).toString('base64url');
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
  await rejectTicket(ticket('wrong-state', { vehicle_state_version: 999 }), 'signed unsupported vehicle state schema rejected');
  await rejectTicket(ticket('old-vehicle', { loadout_hash: 'prototype-v1' }), 'signed old vehicle simulation rejected');
  await rejectTicket(ticket('sharp-box-vehicle', { loadout_hash: 'prototype-v2' }), 'signed sharp-box vehicle simulation rejected');
  await rejectTicket(ticket('wrong-track', { track: { ...compatibility.track, simulation_hash: 'a'.repeat(64) } }), 'signed stale track hash rejected');
  for (const [label, descriptor] of [
    ['stale hello protocol', { ...compatibility, protocol_version: 1 }],
    ['unsupported hello state schema', { ...compatibility, vehicle_state_version: 999 }],
    ['old hello vehicle simulation', { ...compatibility, loadout_hash: 'prototype-v1' }],
    ['sharp-box hello vehicle simulation', { ...compatibility, loadout_hash: 'prototype-v2' }],
    ['stale hello track', { ...compatibility, track: { ...compatibility.track, simulation_hash: 'a'.repeat(64) } }],
  ]) {
    const peer = await connect(ticket('incompatible-client'), descriptor);
    await waitFor(() => peer.closed, `${label} close`);
    verify(peer.reason === 'update_required' && !peer.messages.some(message => message.type === 'welcome'), `${label} rejected before racer admission`);
  }
  const first = await joined('driver-a', goodTicket);
  await rejectTicket(goodTicket, 'ticket replay rejected');
  const second = await joined('driver-b');
  await waitFor(() => first.messages.find(message => message.type === 'snapshot' && message.players.length === 2), 'two-player snapshot');
  verify(true, 'two real WebSocket clients share authoritative snapshot');
  await waitFor(() => first.messages.find(message => message.type === 'snapshot' && message.countdown === 0), 'countdown complete');
  const before = ownState(first, 'driver-a').state.position;
  let sequence = first.ack;
  for (let index = 0; index < 60; index++) {
    first.socket.send(JSON.stringify({ type: 'input', sequence: ++sequence, steering: 0, throttle: 1, brake: 0, drift: false }));
    await delay(1000 / 60);
  }
  const driven = await waitFor(() => ownState(first, 'driver-a', player => player.ack >= sequence), 'input acknowledgement');
  verify(Math.hypot(...driven.state.position.map((value, index) => value - before[index])) > 3, 'server advances car from validated input');
  await delay(1300);
  const stopped = ownState(first, 'driver-a');
  verify(Math.hypot(stopped.state.velocity[0], stopped.state.velocity[2]) < 0.5, 'stale input brakes authoritative car');
  first.socket.close();
  await waitFor(() => first.closed, 'disconnect');
  const resumed = await joined('driver-a');
  verify(resumed.ack === sequence, 'new signed ticket reconnects with acknowledged sequence');
  const resumedState = await waitFor(() => ownState(resumed, 'driver-a'), 'resumed snapshot');
  verify(Math.hypot(...resumedState.state.position.map((value, index) => value - stopped.state.position[index])) < 0.5, 'reconnect preserves server position');
  resumed.socket.send(JSON.stringify({ type: 'input', sequence, steering: 0, throttle: 1, brake: 0, drift: false }));
  await waitFor(() => resumed.closed, 'sequence replay close');
  verify(resumed.reason === 'invalid_input', 'replayed input sequence rejected');
  const malformed = await joined('driver-a');
  malformed.socket.send(JSON.stringify({ type: 'input', sequence: sequence + 1, steering: null, throttle: 1, brake: 0, drift: false }));
  await waitFor(() => malformed.closed, 'non-numeric input close');
  verify(malformed.reason === 'invalid_input', 'non-numeric input rejected over socket');
  const unknown = await joined('driver-a');
  unknown.socket.send(JSON.stringify({ type: 'grant_money', amount: 1000 }));
  await waitFor(() => unknown.closed, 'unknown packet close');
  verify(unknown.reason === 'unknown_packet', 'unknown packet cannot mutate economy or simulation');
  const flooding = await joined('driver-a');
  for (let index = 0; index < 110; index++) flooding.socket.send(JSON.stringify({ type: 'ping', sent: index }));
  await waitFor(() => flooding.closed, 'flood close');
  verify(flooding.reason === 'rate_limit', 'packet rate limit enforced');
  for (let index = 2; index < 10; index++) await joined(`slot-${index}`);
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
