import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { access, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { createConnection, createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { Pool } from 'pg';
import { readConfig } from '../src/config.js';
import { startLocalDatabase } from '../src/local-database.js';
import { withLocalShutdown } from '../src/local-lifecycle.js';
import { bundledPostgresBin, NativePostgres } from '../src/native-postgres.js';

function deferred() {
  let resolve!: () => void;
  const promise = new Promise<void>((done) => { resolve = done; });
  return { promise, resolve };
}

function assertDetached(signals: EventEmitter) {
  assert.equal(signals.listenerCount('SIGINT'), 0);
  assert.equal(signals.listenerCount('SIGTERM'), 0);
}

test('startup errors close acquired resources and remove signal handlers', async () => {
  const signals = new EventEmitter();
  let stops = 0;
  const error = new Error('configuration rejected');
  await assert.rejects(withLocalShutdown(async (lifecycle) => {
    lifecycle.own(async () => { stops++; });
    throw error;
  }, signals), (actual) => actual === error);
  assert.equal(stops, 1);
  assertDetached(signals);
});

test('signal during acquisition closes the late resource without starting the next stage', async () => {
  const signals = new EventEmitter(), acquired = deferred();
  let stops = 0, proceeded = false;
  const running = withLocalShutdown(async (lifecycle) => {
    await acquired.promise;
    lifecycle.own(async () => { stops++; });
    lifecycle.checkpoint();
    proceeded = true;
  }, signals);
  signals.emit('SIGTERM');
  acquired.resolve();
  await running;
  assert.equal(stops, 1);
  assert.equal(proceeded, false);
  assertDetached(signals);
});

test('shutdown stops PostgreSQL while a pool is still waiting on startup work', async () => {
  const signals = new EventEmitter(), databaseStopped = deferred();
  let databaseStops = 0, poolStops = 0, proceeded = false;
  const running = withLocalShutdown(async (lifecycle) => {
    lifecycle.own(async () => { databaseStops++; databaseStopped.resolve(); });
    lifecycle.own(async () => { poolStops++; await databaseStopped.promise; });
    await databaseStopped.promise;
    lifecycle.checkpoint();
    proceeded = true;
  }, signals);
  signals.emit('SIGTERM');
  await running;
  assert.equal(databaseStops, 1);
  assert.equal(poolStops, 1);
  assert.equal(proceeded, false);
  assertDetached(signals);
});

test('signals during listen close every resource once, including repeated signals', async () => {
  const signals = new EventEmitter(), listening = deferred(), appClosed = deferred();
  const stops = [0, 0, 0];
  const running = withLocalShutdown(async (lifecycle) => {
    for (let index = 0; index < stops.length; index++) {
      lifecycle.own(async () => { stops[index]++; if (index === 2) appClosed.resolve(); });
    }
    listening.resolve();
    await appClosed.promise;
    throw new Error('listen cancelled');
  }, signals);
  await listening.promise;
  signals.emit('SIGTERM');
  signals.emit('SIGINT');
  signals.emit('SIGTERM');
  await running;
  assert.deepEqual(stops, [1, 1, 1]);
  assertDetached(signals);
});

test('a failed close does not skip the remaining resources and is reported', async () => {
  const signals = new EventEmitter();
  let stops = 0;
  const running = withLocalShutdown(async (lifecycle) => {
    lifecycle.own(async () => { stops++; });
    lifecycle.own(async () => { throw new Error('close failed'); });
    lifecycle.stop();
  }, signals);
  await assert.rejects(running, /Local resource cleanup failed/);
  assert.equal(stops, 1);
  assertDetached(signals);
});

async function freePort() {
  const socket = createServer();
  await new Promise<void>((done) => socket.listen(0, '127.0.0.1', done));
  const port = (socket.address() as { port: number }).port;
  await new Promise<void>((done) => socket.close(() => done()));
  return port;
}

async function assertPortClosed(port: number) {
  await new Promise<void>((done, fail) => {
    const socket = createConnection({ host: '127.0.0.1', port });
    socket.once('error', (error: NodeJS.ErrnoException) => {
      socket.destroy();
      if (error.code === 'ECONNREFUSED') done(); else fail(error);
    });
    socket.once('connect', () => { socket.destroy(); fail(new Error('PostgreSQL was left listening')); });
    socket.setTimeout(1000, () => { socket.destroy(); fail(new Error('Port check timed out')); });
  });
}

test('invalid local configuration stops a real acquired PostgreSQL process', { timeout: 60000 }, async () => {
  for (const invalid of [{ SESSION_SECRET: 'short' }, { HOST: '0.0.0.0' }]) {
    const signals = new EventEmitter(), port = await freePort();
    const directory = await mkdtemp(join(tmpdir(), 'gnom-config-stop-'));
    await assert.rejects(withLocalShutdown(async (lifecycle) => {
      const local = await startLocalDatabase(directory, port, {
        signal: lifecycle.signal,
        onStarted: (postgres) => lifecycle.own(() => postgres.stop()),
      });
      readConfig({ DEPLOYMENT_ENV: 'local', DATABASE_URL: local.databaseUrl, SESSION_SECRET: 'test-session-secret-at-least-32-characters', ...invalid });
    }, signals), /SESSION_SECRET|loopback/);
    await assertPortClosed(port);
    await rm(directory, { recursive: true, force: true });
    assertDetached(signals);
  }
});

test('SIGTERM during a real startup query closes PostgreSQL and drains its pool', { timeout: 60000 }, async () => {
  const signals = new EventEmitter(), port = await freePort();
  const directory = await mkdtemp(join(tmpdir(), 'gnom-query-stop-'));
  let queryInterrupted = false, proceeded = false;
  await withLocalShutdown(async (lifecycle) => {
    const local = await startLocalDatabase(directory, port, {
      signal: lifecycle.signal,
      onStarted: (postgres) => lifecycle.own(() => postgres.stop()),
    });
    const pool = new Pool({ connectionString: local.databaseUrl });
    lifecycle.own(() => pool.end());
    const client = await pool.connect();
    try {
      await pool.query('SELECT 1');
      assert.equal(pool.idleCount, 1);
      const query = client.query('SELECT pg_sleep(60)');
      setImmediate(() => signals.emit('SIGTERM'));
      await query;
    } catch (error) { queryInterrupted = true; throw error; }
    finally { client.release(); }
    lifecycle.checkpoint();
    proceeded = true;
  }, signals);
  assert.equal(queryInterrupted, true);
  assert.equal(proceeded, false);
  await assertPortClosed(port);
  await rm(directory, { recursive: true, force: true });
  assertDetached(signals);
});

test('an already cancelled database acquisition cannot create a PostgreSQL process', async () => {
  const controller = new AbortController();
  controller.abort();
  let acquired = false;
  await assert.rejects(startLocalDatabase(join(tmpdir(), 'gnom-never-created'), 1, {
    signal: controller.signal,
    onStarted: () => { acquired = true; },
  }), { name: 'AbortError' });
  assert.equal(acquired, false);
});

test('the pinned platform package exposes the default PostgreSQL binaries', async () => {
  const bin = await bundledPostgresBin();
  await access(join(bin, 'postgres'));
  await access(join(bin, 'initdb'));
});

test('cancelling native acquisition stops the spawned PostgreSQL before readiness', { timeout: 60000 }, async () => {
  const directory = await mkdtemp(join(tmpdir(), 'gnom-native-cancel-'));
  const passwordFile = join(directory, 'password'), password = 'isolated-lifecycle-test-password';
  await writeFile(passwordFile, password, { mode: 0o600 });
  const port = await freePort();
  const postgres = new NativePostgres({
    bin: process.env.PG_BIN_DIR ?? await bundledPostgresBin(), databaseDir: join(directory, 'cluster'),
    socketDir: directory, passwordFile, password, port, user: 'gnom_local',
  });
  const controller = new AbortController();
  try {
    await postgres.initialise();
    const start = postgres.start(controller.signal);
    controller.abort();
    await assert.rejects(start, { name: 'AbortError' });
    await assertPortClosed(port);
  } finally {
    await postgres.stop();
    await rm(directory, { recursive: true, force: true });
  }
});

test('cancelling initdb waits for its owned process to close', { timeout: 60000 }, async () => {
  const directory = await mkdtemp(join(tmpdir(), 'gnom-init-cancel-'));
  const passwordFile = join(directory, 'password'), password = 'isolated-lifecycle-test-password';
  await writeFile(passwordFile, password, { mode: 0o600 });
  const postgres = new NativePostgres({
    bin: process.env.PG_BIN_DIR ?? await bundledPostgresBin(), databaseDir: join(directory, 'cluster'),
    socketDir: directory, passwordFile, password, port: await freePort(), user: 'gnom_local',
  });
  const controller = new AbortController();
  try {
    const initialise = postgres.initialise(controller.signal);
    controller.abort();
    await assert.rejects(initialise, { name: 'AbortError' });
  } finally { await rm(directory, { recursive: true, force: true }); }
});
