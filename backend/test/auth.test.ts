import assert from 'node:assert/strict';
import { after, before, beforeEach, test } from 'node:test';
import { createHmac, randomUUID } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:net';
import { Pool } from 'pg';
import type { FastifyInstance } from 'fastify';
import { startLocalDatabase } from '../src/local-database.js';
import { readConfig, type Config } from '../src/config.js';
import { migrate } from '../src/database.js';
import { buildApp } from '../src/app.js';
import { AuthService } from '../src/auth.js';
import { loadTrackManifest, raceCompatibility, STYLE_IDS, TICKET_VERSION } from '../src/race-compatibility.js';

let local: Awaited<ReturnType<typeof startLocalDatabase>>;
let directory: string;
let pool: Pool, app: FastifyInstance, config: Config;
const environment = { DEPLOYMENT_ENV: 'test', DEV_AUTH_ENABLED: 'true', SESSION_SECRET: 'test-session-secret-at-least-32-characters', RACE_TICKET_SECRET: 'test-race-secret-at-least-32-characters' };
type Browser = { cookie: string; csrfToken: string; user: { id: string; kind: string }; mergeAvailable: boolean };

before(async () => {
  const socket = createServer();
  await new Promise<void>((done) => socket.listen(0, '127.0.0.1', done));
  const port = (socket.address() as { port: number }).port;
  await new Promise<void>((done) => socket.close(() => done()));
  directory = await mkdtemp(join(tmpdir(), 'gnom-auth-test-'));
  local = await startLocalDatabase(directory, port);
  config = readConfig({ ...environment, DATABASE_URL: local.databaseUrl });
  pool = new Pool({ connectionString: local.databaseUrl, max: 10 });
  console.log((await pool.query('SELECT version()')).rows[0].version);
  await migrate(pool, config);
  app = await buildApp(config, pool, { staticRoot: false });
});
beforeEach(async () => {
  await pool.query('TRUNCATE guest_merge,auth_attempt,game_session,guest_profile,account_identity,account CASCADE');
  await migrate(pool, config);
});
after(async () => {
  await app?.close();
  await pool?.end();
  await local?.postgres.stop();
  if (directory) await rm(directory, { recursive: true, force: true });
});

function browser(response: { json(): any; cookies: { name: string; value: string }[] }, previous?: Browser): Browser {
  const session = response.cookies.find((cookie) => cookie.name === config.cookieName);
  return { ...response.json(), cookie: session ? `${session.name}=${session.value}` : previous?.cookie };
}
async function guest() { return browser(await app.inject({ method: 'GET', url: '/api/auth/bootstrap' })); }
async function post(client: Browser, url: string, payload: object, headers: Record<string, string> = {}) {
  return app.inject({ method: 'POST', url, payload, headers: { cookie: client.cookie, origin: config.origin, 'x-csrf-token': client.csrfToken, ...headers } });
}
async function login(client: Browser, profileId = 'dev-1') {
  const attempt = (await post(client, '/api/auth/attempt', { provider: 'dev' })).json();
  const response = await post(client, '/api/auth/dev', { ...attempt, profileId });
  assert.equal(response.statusCode, 200, response.body);
  return browser(response);
}

test('runtime has explicit environment, loopback and public dev fail-closed guards', () => {
  const base = { DATABASE_URL: local.databaseUrl, SESSION_SECRET: environment.SESSION_SECRET };
  assert.throws(() => readConfig(base), /DEPLOYMENT_ENV/);
  assert.throws(() => readConfig({ ...base, DEPLOYMENT_ENV: 'production', DEV_AUTH_ENABLED: 'true' }), /forbidden/);
  assert.throws(() => readConfig({ ...base, DEPLOYMENT_ENV: 'staging', IDENTITY_PROVIDER: 'dev' }), /forbidden/);
  assert.throws(() => readConfig({ ...base, DEPLOYMENT_ENV: 'local', HOST: '0.0.0.0' }), /loopback/);
  assert.throws(() => readConfig({ ...base, DEPLOYMENT_ENV: 'production', APP_ORIGIN: 'http://example.com' }), /HTTPS/);
});

test('bootstrap creates a database session with HttpOnly cookie and no cleartext token', async () => {
  const response = await app.inject({ method: 'GET', url: '/api/auth/bootstrap' });
  assert.equal(response.statusCode, 200);
  assert.match(response.headers['set-cookie'] as string, /HttpOnly/);
  assert.match(response.headers['set-cookie'] as string, /SameSite=Lax/);
  assert.equal(response.headers['cache-control'], 'no-store');
  const data = browser(response);
  assert.equal(data.user.kind, 'guest');
  assert.equal(response.json().devProfiles.length, 3);
  const stored = (await pool.query('SELECT * FROM game_session')).rows[0];
  assert.equal(stored.token_hash.length, 64);
  assert.notEqual(stored.token_hash, data.cookie.split('=')[1]);
  assert.equal((await app.inject({ method: 'GET', url: '/api/account/progress', headers: { cookie: data.cookie } })).statusCode, 403);
  assert.equal((await app.inject({ method: 'GET', url: '/api/auth/bootstrap', headers: { origin: 'https://evil.example' } })).statusCode, 403);
});

test('login rotates session and CSRF; replay and revoked session fail', async () => {
  const old = await guest();
  const attempt = (await post(old, '/api/auth/attempt', { provider: 'dev' })).json();
  const proof = { ...attempt, profileId: 'dev-1' };
  const response = await post(old, '/api/auth/dev', proof);
  assert.equal(response.statusCode, 200, response.body);
  const account = browser(response);
  assert.equal(account.user.kind, 'account');
  assert.notEqual(account.cookie, old.cookie);
  assert.notEqual(account.csrfToken, old.csrfToken);
  assert.equal(account.mergeAvailable, true);
  assert.equal((await post(old, '/api/auth/dev', proof)).statusCode, 401);
  assert.equal((await post(account, '/api/auth/dev', proof)).statusCode, 401);
  assert.equal((await app.inject({ method: 'GET', url: '/api/me', headers: { cookie: old.cookie } })).statusCode, 401);
  const logout = await post(account, '/api/auth/logout', {});
  assert.equal(logout.statusCode, 200);
  assert.equal(logout.json().user.id, old.user.id);
  assert.equal((await app.inject({ method: 'GET', url: '/api/me', headers: { cookie: account.cookie } })).statusCode, 401);
});

test('origin, CSRF, arbitrary IDs, roles and injected balances are rejected', async () => {
  const client = await guest();
  assert.equal((await post(client, '/api/auth/attempt', { provider: 'dev' }, { origin: 'https://evil.example' })).statusCode, 403);
  assert.equal((await post(client, '/api/auth/attempt', { provider: 'dev' }, { 'x-csrf-token': 'wrong' })).statusCode, 403);
  const attempt = (await post(client, '/api/auth/attempt', { provider: 'dev' })).json();
  assert.equal((await post(client, '/api/auth/dev', { ...attempt, profileId: randomUUID() })).statusCode, 400);
  assert.equal((await post(client, '/api/auth/dev', { ...attempt, profileId: 'dev-1', role: 'admin' })).statusCode, 400);
  assert.equal((await post(client, '/api/auth/dev', { ...attempt, profileId: 'dev-1', balance: 10000 })).statusCode, 400);
  assert.equal((await post(client, '/api/auth/dev', { ...attempt, profileId: 'dev-1', dev: true })).statusCode, 400);
  assert.equal((await app.inject({ method: 'GET', url: '/api/me', headers: { cookie: client.cookie } })).json().user.kind, 'guest');
});

test('attempt is browser-bound, expiring, and nonce is validated', async () => {
  const first = await guest(), second = await guest();
  const attempt = (await post(first, '/api/auth/attempt', { provider: 'dev' })).json();
  assert.equal((await post(second, '/api/auth/dev', { ...attempt, profileId: 'dev-1' })).statusCode, 401);
  assert.equal((await post(first, '/api/auth/dev', { ...attempt, profileId: 'dev-1', nonce: 'A'.repeat(43) })).statusCode, 401);
  await pool.query("UPDATE auth_attempt SET expires_at=now()-interval '1 second' WHERE id=$1", [attempt.attemptId]);
  assert.equal((await post(first, '/api/auth/dev', { ...attempt, profileId: 'dev-1' })).statusCode, 401);
  assert.equal((await app.inject({ method: 'GET', url: '/api/me', headers: { cookie: first.cookie } })).json().user.id, first.user.id);
});

test('concurrent login can consume one attempt only once', async () => {
  const client = await guest();
  const attempt = (await post(client, '/api/auth/attempt', { provider: 'dev' })).json();
  const results = await Promise.all([post(client, '/api/auth/dev', { ...attempt, profileId: 'dev-1' }), post(client, '/api/auth/dev', { ...attempt, profileId: 'dev-1' })]);
  assert.deepEqual(results.map((r) => r.statusCode).sort(), [200, 401]);
});

test('guest merge is explicit, server-owned and idempotent under concurrent retries', async () => {
  const old = await guest();
  await pool.query('UPDATE guest_profile SET practice_finishes=3 WHERE id=$1', [old.user.id]);
  const account = await login(old);
  assert.equal((await app.inject({ method: 'GET', url: '/api/me', headers: { cookie: account.cookie } })).json().progress.practiceFinishes, 0);
  const request = { targetAccountId: account.user.id, confirmed: true, mergeId: randomUUID() };
  assert.equal((await post(account, '/api/guest/merge', { ...request, confirmed: false })).statusCode, 403);
  assert.equal((await post(account, '/api/guest/merge', { ...request, targetAccountId: randomUUID() })).statusCode, 403);
  assert.equal((await post(account, '/api/guest/merge', { ...request, guestId: randomUUID() })).statusCode, 400);
  const results = await Promise.all([post(account, '/api/guest/merge', request), post(account, '/api/guest/merge', request)]);
  assert.deepEqual(results.map((response) => response.statusCode), [200, 200]);
  assert.equal(results[1].json().progress.practiceFinishes, 3);
  assert.equal((await post(account, '/api/guest/merge', { ...request, mergeId: randomUUID() })).json().progress.practiceFinishes, 3);
  assert.equal((await pool.query('SELECT count(*)::int AS count FROM guest_merge')).rows[0].count, 1);
  assert.equal((await app.inject({ method: 'GET', url: '/api/me', headers: { cookie: account.cookie } })).json().mergeAvailable, false);
});

test('ticket is signed, short-lived and issued only with session and CSRF', async () => {
  const client = await guest();
  assert.equal((await app.inject({ method: 'POST', url: '/api/race/ticket', payload: {}, headers: { origin: config.origin } })).statusCode, 401);
  assert.equal((await post(client, '/api/race/ticket', {}, { 'x-csrf-token': 'invalid' })).statusCode, 403);
  const result = (await post(client, '/api/race/ticket', {})).json();
  const [body, signature] = result.ticket.split('.');
  assert.equal(signature, createHmac('sha256', config.raceTicketSecret!).update(body).digest('base64url'));
  const payload = JSON.parse(Buffer.from(body, 'base64url').toString());
  assert.equal(payload.player_id, client.user.id);
  assert.equal(payload.match_id, 'prototype-1');
  assert.equal(payload.style_id, 'handling');
  assert.equal(result.styleId, 'handling');
  assert.ok(payload.expires_at <= Math.floor(Date.now() / 1000) + 60);
  assert.ok(payload.expires_at > Math.floor(Date.now() / 1000));
  const track = loadTrackManifest(config.trackManifestPath);
  assert.equal(payload.v, TICKET_VERSION);
  assert.deepEqual(result.track, track);
  assert.deepEqual(result.compatibility, raceCompatibility(track));
  assert.equal(payload.protocol_version, result.compatibility.protocol_version);
  assert.equal(payload.vehicle_state_version, result.compatibility.vehicle_state_version);
  assert.deepEqual(payload.track, result.compatibility.track);
  assert.equal(payload.track.simulation_hash, track.simulation_hash);
  assert.equal(payload.track.track_id, track.track_id);
  const account = await login(client);
  assert.equal((await post(account, '/api/race/ticket', {})).json().playerId, account.user.id);
});

test('all four styles are signed without accepting client-owned vehicle stats', async () => {
  const client = await guest();
  for (const styleId of STYLE_IDS) {
    const response = await post(client, '/api/race/ticket', { styleId });
    assert.equal(response.statusCode, 200, response.body);
    const result = response.json();
    const [body, signature] = result.ticket.split('.');
    assert.equal(signature, createHmac('sha256', config.raceTicketSecret!).update(body).digest('base64url'));
    const payload = JSON.parse(Buffer.from(body, 'base64url').toString());
    assert.equal(payload.style_id, styleId);
    assert.equal(result.styleId, styleId);
    assert.equal(payload.player_id, client.user.id);
    assert.equal(payload.loadout_hash, 'prototype-v7');
    assert.equal(payload.protocol_version, 5);
    assert.equal(payload.v, 3);
  }
  for (const payload of [
    { styleId: 'balanced' }, { styleId: '' }, { styleId: 'SPEED' },
    { styleId: null }, { styleId: 1 }, { styleId: ['drift'] },
    { styleId: 'speed', topSpeed: 999 }, { styleId: 'drift', stats: { grip: 999 } },
    { style_id: 'speed' }, { loadout_hash: 'prototype-v6' },
  ]) {
    const response = await post(client, '/api/race/ticket', payload);
    assert.equal(response.statusCode, 400, JSON.stringify(payload));
    assert.equal(response.json().error, 'invalid_request');
  }
});

test('style selection preserves origin, CSRF and session protections', async () => {
  const client = await guest();
  const payload = { styleId: 'drift' };
  assert.equal((await app.inject({ method: 'POST', url: '/api/race/ticket', payload, headers: { origin: config.origin } })).statusCode, 401);
  assert.equal((await post(client, '/api/race/ticket', payload, { origin: 'https://evil.example' })).statusCode, 403);
  assert.equal((await post(client, '/api/race/ticket', payload, { 'x-csrf-token': 'invalid' })).statusCode, 403);
  const account = await login(client);
  assert.equal((await post(client, '/api/race/ticket', payload)).statusCode, 401);
  assert.equal((await post(account, '/api/race/ticket', payload)).json().styleId, 'drift');
});

test('race startup fails closed for a missing or untrusted manifest path', () => {
  assert.throws(() => new AuthService(pool, { ...config, trackManifestPath: join(directory, 'absent-track.json') }), /ENOENT/);
});

test('expired sessions reject account API and changing deployment rejects database', async () => {
  const client = await login(await guest());
  await pool.query("UPDATE game_session SET expires_at=now()-interval '1 second'");
  assert.equal((await app.inject({ method: 'GET', url: '/api/account/progress', headers: { cookie: client.cookie } })).statusCode, 401);
  await assert.rejects(buildApp({ ...config, environment: 'production', devAuth: false }, pool, { staticRoot: false }), /environment mismatch/);
});

test('disabled dev flag removes endpoints and invalidates dev sessions', async () => {
  const client = await login(await guest());
  const disabled = await buildApp({ ...config, devAuth: false }, pool, { staticRoot: false });
  try {
    assert.equal((await disabled.inject({ method: 'POST', url: '/api/auth/dev', payload: {} })).statusCode, 404);
    assert.equal((await disabled.inject({ method: 'POST', url: '/api/auth/attempt', payload: {} })).statusCode, 404);
    assert.equal((await disabled.inject({ method: 'GET', url: '/api/auth/bootstrap' })).json().devProfiles.length, 0);
    assert.equal((await disabled.inject({ method: 'GET', url: '/api/me', headers: { cookie: client.cookie } })).statusCode, 401);
  } finally { await disabled.close(); }
});

test('public boot has no dev endpoints and rejects a copied dev session even with matching marker', async () => {
  const client = await login(await guest());
  const publicConfig = readConfig({ ...environment, DEPLOYMENT_ENV: 'production', DEV_AUTH_ENABLED: 'false', DATABASE_URL: local.databaseUrl, APP_ORIGIN: 'https://game.example', RACE_WEBSOCKET_URL: 'wss://race.example' });
  const service = new AuthService(pool, publicConfig);
  const rawToken = client.cookie.split('=')[1];
  await pool.query("UPDATE app_environment SET environment='production'");
  await pool.query(`INSERT INTO game_session(token_hash,environment,account_id,pending_guest_id,provider,expires_at)
    SELECT $1,'production',account_id,pending_guest_id,provider,expires_at FROM game_session WHERE account_id IS NOT NULL`, [service.tokenHash(rawToken)]);
  const production = await buildApp(publicConfig, pool, { staticRoot: false });
  try {
    assert.equal((await production.inject({ method: 'POST', url: '/api/auth/dev', payload: {} })).statusCode, 404);
    assert.equal((await production.inject({ method: 'GET', url: '/api/me', headers: { cookie: `${publicConfig.cookieName}=${rawToken}` } })).statusCode, 401);
    const anonymous = await production.inject({ method: 'GET', url: '/api/auth/bootstrap' });
    assert.match(anonymous.headers['set-cookie'] as string, /; Secure/);
    assert.equal(anonymous.json().devProfiles.length, 0);
  } finally {
    await production.close();
    await pool.query("UPDATE app_environment SET environment='test'");
  }
});
