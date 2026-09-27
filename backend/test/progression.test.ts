import assert from 'node:assert/strict';
import { after, before, test } from 'node:test';
import { randomUUID } from 'node:crypto';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { createServer } from 'node:net';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Pool } from 'pg';
import type { FastifyInstance } from 'fastify';
import { buildApp } from '../src/app.js';
import { readConfig, type Config } from '../src/config.js';
import { migrate } from '../src/database.js';
import { startLocalDatabase } from '../src/local-database.js';
import { ProgressionError, ProgressionService } from '../src/progression.js';

let directory: string;
let local: Awaited<ReturnType<typeof startLocalDatabase>>;
let pool: Pool, config: Config, app: FastifyInstance, progression: ProgressionService;
let accountId: string, otherAccountId: string;
const environment = {
  DEPLOYMENT_ENV: 'test', DEV_AUTH_ENABLED: 'true',
  SESSION_SECRET: 'progression-test-session-secret-at-least-32-characters',
  RACE_TICKET_SECRET: 'progression-test-race-secret-at-least-32-characters',
};

before(async () => {
  const socket = createServer();
  await new Promise<void>((done) => socket.listen(0, '127.0.0.1', done));
  const port = (socket.address() as { port: number }).port;
  await new Promise<void>((done) => socket.close(() => done()));
  directory = await mkdtemp(join(tmpdir(), 'gnom-progression-test-'));
  local = await startLocalDatabase(directory, port);
  config = readConfig({ ...environment, DATABASE_URL: local.databaseUrl });
  pool = new Pool({ connectionString: local.databaseUrl, max: 12 });
  await migrate(pool, config);
  progression = new ProgressionService(pool);
  app = await buildApp(config, pool, { staticRoot: false });
  const accounts = await pool.query("SELECT subject, account_id FROM account_identity WHERE provider='dev' ORDER BY subject");
  accountId = accounts.rows[0].account_id;
  otherAccountId = accounts.rows[1].account_id;
});

after(async () => {
  await app?.close();
  await pool?.end();
  await local?.postgres.stop();
  if (directory) await rm(directory, { recursive: true, force: true });
});

function rejectsCode(code: string) {
  return (error: unknown) => error instanceof ProgressionError && error.code === code;
}

async function isolatedDatabase(name: string, work: (database: Pool, databaseConfig: Config) => Promise<void>) {
  await pool.query(`CREATE DATABASE ${name}`);
  const url = new URL(local.databaseUrl);
  url.pathname = `/${name}`;
  const database = new Pool({ connectionString: url.toString(), max: 8 });
  const databaseConfig = readConfig({ ...environment, DATABASE_URL: url.toString() });
  try { await work(database, databaseConfig); }
  finally {
    await database.end();
    await pool.query(`DROP DATABASE ${name}`);
  }
}

test('concurrent and repeated migrations apply the known files exactly once', async () => {
  await Promise.all(Array.from({ length: 5 }, () => migrate(pool, config)));
  const history = await pool.query('SELECT id, checksum FROM schema_migration ORDER BY id');
  assert.deepEqual(history.rows.map((row) => row.id), ['001_auth.sql', '002_progression.sql']);
  for (const row of history.rows) assert.match(row.checksum, /^[a-f0-9]{64}$/);
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM account_identity')).rows[0].total, 3);
  await isolatedDatabase('concurrent_first_migration', async (database, databaseConfig) => {
    await Promise.all(Array.from({ length: 5 }, () => migrate(database, databaseConfig)));
    assert.deepEqual((await database.query('SELECT id FROM schema_migration ORDER BY id')).rows.map((row) => row.id), ['001_auth.sql', '002_progression.sql']);
    assert.equal((await database.query('SELECT count(*)::int AS total FROM account_identity')).rows[0].total, 3);
    assert.equal((await database.query('SELECT count(*)::int AS total FROM account')).rows[0].total, 3);
    assert.equal((await database.query('SELECT count(*)::int AS total FROM catalog_version')).rows[0].total, 0);
  });
});

test('legacy auth-only database upgrades without replacing identities, accounts or active sessions', async () => {
  await isolatedDatabase('legacy_upgrade', async (database, databaseConfig) => {
    await database.query(await readFile(new URL('../migrations/001_auth.sql', import.meta.url), 'utf8'));
    const id = randomUUID(), token = 'a'.repeat(64);
    await database.query("INSERT INTO app_environment(environment) VALUES('test')");
    await database.query("INSERT INTO account(id,display_name,practice_finishes) VALUES($1,'Existing driver',7)", [id]);
    await database.query("INSERT INTO account_identity(provider,issuer,subject,account_id) VALUES('dev','urn:gnom-fiji:dev','dev-1',$1)", [id]);
    await database.query("INSERT INTO game_session(token_hash,environment,account_id,provider,expires_at) VALUES($1,'test',$2,'dev',now()+interval '1 hour')", [token, id]);
    await migrate(database, databaseConfig);
    await migrate(database, databaseConfig);
    assert.deepEqual((await database.query('SELECT id,display_name,practice_finishes FROM account WHERE id=$1', [id])).rows[0], {
      id, display_name: 'Existing driver', practice_finishes: 7,
    });
    assert.equal((await database.query("SELECT account_id FROM account_identity WHERE subject='dev-1'")).rows[0].account_id, id);
    assert.equal((await database.query('SELECT account_id FROM game_session WHERE token_hash=$1 AND revoked_at IS NULL AND expires_at>now()', [token])).rows[0].account_id, id);
    assert.equal((await database.query('SELECT count(*)::int AS total FROM schema_migration')).rows[0].total, 2);
    assert.equal((await database.query('SELECT count(*)::int AS total FROM reward_operation')).rows[0].total, 0);
  });
});

test('migration checksum tampering and unknown future migrations fail closed', async () => {
  await isolatedDatabase('migration_history_guards', async (database, databaseConfig) => {
    await migrate(database, databaseConfig);
    const original = (await database.query("SELECT checksum FROM schema_migration WHERE id='001_auth.sql'")).rows[0].checksum;
    await database.query("UPDATE schema_migration SET checksum=$1 WHERE id='001_auth.sql'", ['0'.repeat(64)]);
    await assert.rejects(migrate(database, databaseConfig), /Database migration checksum mismatch: 001_auth.sql/);
    await database.query("UPDATE schema_migration SET checksum=$1 WHERE id='001_auth.sql'", [original]);
    await database.query("INSERT INTO schema_migration(id,checksum) VALUES('999_future.sql',$1)", ['f'.repeat(64)]);
    await assert.rejects(migrate(database, databaseConfig), /Database contains unsupported migration: 999_future.sql/);
    assert.equal((await database.query('SELECT count(*)::int AS total FROM account_identity')).rows[0].total, 3);
  });
});

test('wrong deployment environment rolls the legacy upgrade back atomically', async () => {
  await isolatedDatabase('migration_environment_guard', async (database, databaseConfig) => {
    await database.query(await readFile(new URL('../migrations/001_auth.sql', import.meta.url), 'utf8'));
    await database.query("INSERT INTO app_environment(environment) VALUES('production')");
    await assert.rejects(migrate(database, databaseConfig), /Database environment mismatch/);
    assert.equal((await database.query("SELECT to_regclass('schema_migration') AS table_name")).rows[0].table_name, null);
    assert.equal((await database.query("SELECT to_regclass('catalog_version') AS table_name")).rows[0].table_name, null);
    assert.equal((await database.query('SELECT environment FROM app_environment')).rows[0].environment, 'production');
    assert.equal((await database.query('SELECT count(*)::int AS total FROM account')).rows[0].total, 0);
  });
});

async function catalogFixture(count = 3) {
  const version = `test-${randomUUID()}`;
  const items = Array.from({ length: count }, (_, index) => ({
    id: `fixture-${randomUUID()}`, kind: 'cosmetic',
    definition: { label: `Test fixture ${index}`, metadata: { fixture: true, index } },
  }));
  await progression.publishCatalog({ version, items });
  return { version, items, ids: items.map((item) => item.id).sort() };
}

function grantInput(catalogVersion: string, items: string[], owner = accountId) {
  return { operationId: randomUUID(), accountId: owner, catalogVersion, source: 'test-fixture', items };
}

test('catalog publication is immutable, canonical and order-independent', async () => {
  const fixture = await catalogFixture();
  const replay = {
    version: fixture.version,
    items: [...fixture.items].reverse().map((item) => ({
      definition: { metadata: { index: item.definition.metadata.index, fixture: true }, label: item.definition.label },
      kind: item.kind, id: item.id,
    })),
  };
  assert.deepEqual(await progression.publishCatalog(replay), { version: fixture.version, itemCount: 3 });
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM catalog_definition WHERE catalog_version=$1', [fixture.version])).rows[0].total, 3);
  const changed = fixture.items.map((item, index) => index ? item : { ...item, definition: { ...item.definition, label: 'Changed' } });
  await assert.rejects(progression.publishCatalog({ version: fixture.version, items: changed }), rejectsCode('catalog_conflict'));
  const nextVersion = `test-${randomUUID()}`;
  await assert.rejects(progression.publishCatalog({ version: nextVersion, items: [{ ...fixture.items[0], kind: 'part' }] }), rejectsCode('item_kind_conflict'));
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM catalog_version WHERE version=$1', [nextVersion])).rows[0].total, 0);
});

test('catalog JSON preserves literal prototype-like keys without mutating object prototypes', async () => {
  const version = `test-${randomUUID()}`, id = `fixture-${randomUUID()}`;
  const definition = JSON.parse('{"__proto__":{"polluted":true},"constructor":{"label":"fixture"},"nested":{"z":2,"a":1}}');
  await progression.publishCatalog({ version, items: [{ id, kind: 'cosmetic', definition }] });
  const stored = (await pool.query('SELECT definition FROM catalog_definition WHERE catalog_version=$1 AND item_id=$2', [version, id])).rows[0].definition;
  assert.deepEqual(stored, definition);
  assert.equal(Object.hasOwn(stored, '__proto__'), true);
  assert.equal(({} as { polluted?: boolean }).polluted, undefined);
  const reordered = JSON.parse('{"nested":{"a":1,"z":2},"constructor":{"label":"fixture"},"__proto__":{"polluted":true}}');
  assert.deepEqual(await progression.publishCatalog({ version, items: [{ id, kind: 'cosmetic', definition: reordered }] }), { version, itemCount: 1 });
});

test('catalog validation rejects malformed definitions and unsupported persistent categories', async () => {
  const item = { id: 'fixture-validation', kind: 'cosmetic', definition: {} };
  const version = `test-${randomUUID()}`;
  const circular: Record<string, unknown> = {};
  circular.self = circular;
  let deep: Record<string, unknown> = {};
  for (let index = 0; index < 16; index++) deep = { nested: deep };
  const invalid: unknown[] = [
    null, [], { version, items: [] }, { version, items: new Array(1) }, { version, items: [item], extra: true },
    { version: 'UPPERCASE', items: [item] }, { version, items: [item, item] },
    { version, items: [{ ...item, quantity: 1 }] },
    ...['currency', 'race_shard', '', null].map((kind) => ({ version, items: [{ ...item, kind }] })),
    ...[null, [], 'text', { value: Infinity }, { value: undefined }, { value: 1n },
      { value: '\0' }, { value: '\ud800' }, { '\0': true }, { '\ud800': true },
      { value: new Array(1) }, { value: Array.from({ length: 60 }, () => 1e308) },
      circular, deep, { label: 'x'.repeat(17000) }]
      .map((definition) => ({ version, items: [{ ...item, definition }] })),
    { version, items: Array.from({ length: 257 }, (_, index) => ({ ...item, id: `fixture-${index}` })) },
  ];
  for (let index = 0; index < invalid.length; index++) {
    await assert.rejects(progression.publishCatalog(invalid[index]), rejectsCode('invalid_catalog'), `invalid catalog ${index}`);
  }
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM catalog_version WHERE version=$1', [version])).rows[0].total, 0);
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM catalog_item WHERE id=$1', [item.id])).rows[0].total, 0);
});

test('concurrent identical entitlement grants create one operation and return the exact same result', async () => {
  const fixture = await catalogFixture();
  const input = grantInput(fixture.version, fixture.ids);
  const results = await Promise.all(Array.from({ length: 8 }, () => progression.grantEntitlements(input)));
  for (const result of results) assert.deepEqual(result, results[0]);
  assert.deepEqual(results[0], {
    operationId: input.operationId, accountId, catalogVersion: fixture.version, source: input.source,
    grants: fixture.ids.map((itemId) => ({ itemId, alreadyOwned: false })),
  });
  assert.deepEqual(await progression.grantEntitlements({ ...input, operationId: input.operationId.toUpperCase(), accountId: accountId.toUpperCase(), items: [...input.items].reverse() }), results[0]);
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM reward_operation WHERE operation_id=$1', [input.operationId])).rows[0].total, 1);
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM reward_grant WHERE operation_id=$1', [input.operationId])).rows[0].total, 3);
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM inventory_entry WHERE grant_operation_id=$1', [input.operationId])).rows[0].total, 3);
});

test('a reused reward operation rejects changed owner, catalog, source or item payload', async () => {
  const fixture = await catalogFixture();
  const input = grantInput(fixture.version, fixture.ids.slice(0, 2));
  const original = await progression.grantEntitlements(input);
  const nextVersion = `test-${randomUUID()}`;
  await progression.publishCatalog({ version: nextVersion, items: fixture.items });
  for (const changed of [
    { ...input, accountId: otherAccountId }, { ...input, catalogVersion: nextVersion },
    { ...input, source: 'other-source' }, { ...input, items: fixture.ids },
  ]) await assert.rejects(progression.grantEntitlements(changed), rejectsCode('operation_conflict'));
  assert.deepEqual(await progression.grantEntitlements(input), original);
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM inventory_entry WHERE item_id=ANY($1::text[]) AND account_id=$2', [fixture.ids, otherAccountId])).rows[0].total, 0);
});

test('distinct concurrent grants with overlapping ownership serialize without duplicate entitlements', async () => {
  const fixture = await catalogFixture();
  const first = grantInput(fixture.version, [fixture.ids[0], fixture.ids[1]]);
  const second = grantInput(fixture.version, [fixture.ids[2], fixture.ids[1]]);
  const results = await Promise.all([progression.grantEntitlements(first), progression.grantEntitlements(second)]);
  const overlap = results.flatMap((result) => result.grants).filter((grant) => grant.itemId === fixture.ids[1]);
  assert.deepEqual(overlap.map((grant) => grant.alreadyOwned).sort(), [false, true]);
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM inventory_entry WHERE item_id=ANY($1::text[]) AND account_id=$2', [fixture.ids, accountId])).rows[0].total, 3);
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM reward_grant WHERE operation_id=ANY($1::uuid[])', [[first.operationId, second.operationId]])).rows[0].total, 4);
  assert.deepEqual(await progression.grantEntitlements(first), results[0]);
  assert.deepEqual(await progression.grantEntitlements(second), results[1]);
});

test('item ownership survives catalog revisions while preserving original acquisition provenance', async () => {
  const fixture = await catalogFixture(1);
  const first = grantInput(fixture.version, fixture.ids);
  await progression.grantEntitlements(first);
  const version = `test-${randomUUID()}`;
  await progression.publishCatalog({ version, items: fixture.items.map((item) => ({ ...item, definition: { ...item.definition, label: 'Revised fixture' } })) });
  const second = grantInput(version, fixture.ids);
  assert.deepEqual((await progression.grantEntitlements(second)).grants, [{ itemId: fixture.ids[0], alreadyOwned: true }]);
  const stored = (await pool.query('SELECT grant_operation_id,catalog_version FROM inventory_entry WHERE account_id=$1 AND item_id=$2', [accountId, fixture.ids[0]])).rows;
  assert.deepEqual(stored, [{ grant_operation_id: first.operationId, catalog_version: fixture.version }]);
});

test('invalid account, catalog or partial item set cannot leave a reward or partial ownership', async () => {
  const fixture = await catalogFixture();
  const missingAccount = grantInput(fixture.version, fixture.ids, randomUUID());
  const missingCatalog = grantInput(`missing-${randomUUID()}`, fixture.ids);
  const partial = grantInput(fixture.version, [fixture.ids[0], `missing-${randomUUID()}`]);
  await assert.rejects(progression.grantEntitlements(missingAccount), rejectsCode('account_not_found'));
  await assert.rejects(progression.grantEntitlements(missingCatalog), rejectsCode('catalog_not_found'));
  await assert.rejects(progression.grantEntitlements(partial), rejectsCode('item_not_in_catalog'));
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM reward_operation WHERE operation_id=ANY($1::uuid[])', [[missingAccount.operationId, missingCatalog.operationId, partial.operationId]])).rows[0].total, 0);
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM inventory_entry WHERE item_id=ANY($1::text[])', [fixture.ids])).rows[0].total, 0);
});

test('entitlement input rejects quantities, duplicates and malformed identifiers without coercion', async () => {
  const fixture = await catalogFixture(1);
  const input = grantInput(fixture.version, fixture.ids);
  const invalid: unknown[] = [
    null, [], { ...input, extra: true }, { ...input, operationId: 'not-uuid' },
    { ...input, accountId: '' }, { ...input, accountId: 123 },
    { ...input, catalogVersion: 'INVALID' }, { ...input, source: 'INVALID' },
    { ...input, items: [] }, { ...input, items: new Array(1) }, { ...input, items: 'fixture' },
    { ...input, items: [null] }, { ...input, items: [fixture.ids[0], fixture.ids[0]] },
    ...[-1, 0, 1, 1.5, '1'].map((quantity) => ({ ...input, quantity })),
    ...[-1, 0, 1, 1.5, '1'].map((quantity) => ({ ...input, items: [{ itemId: fixture.ids[0], quantity }] })),
    { ...input, items: Array.from({ length: 65 }, (_, index) => `fixture-${index}`) },
  ];
  for (let index = 0; index < invalid.length; index++) {
    await assert.rejects(progression.grantEntitlements(invalid[index]), rejectsCode('invalid_grant'), `invalid grant ${index}`);
  }
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM reward_operation WHERE operation_id=$1', [input.operationId])).rows[0].total, 0);
});

test('published catalog and reward journal rows reject direct SQL updates and deletes', async () => {
  const fixture = await catalogFixture(2);
  const input = grantInput(fixture.version, fixture.ids.slice(0, 1));
  const result = await progression.grantEntitlements(input);
  const outside = await catalogFixture(1);
  const attempts: [string, unknown[]][] = [
    ['UPDATE catalog_version SET content_hash=$2 WHERE version=$1', [fixture.version, '0'.repeat(64)]],
    ['UPDATE catalog_version SET published=false WHERE version=$1', [fixture.version]],
    ['DELETE FROM catalog_version WHERE version=$1', [fixture.version]],
    ["UPDATE catalog_item SET kind='part' WHERE id=$1", [fixture.ids[0]]],
    ['DELETE FROM catalog_item WHERE id=$1', [fixture.ids[0]]],
    ["UPDATE catalog_definition SET definition='{}'::jsonb WHERE catalog_version=$1", [fixture.version]],
    ['DELETE FROM catalog_definition WHERE catalog_version=$1', [fixture.version]],
    ["INSERT INTO catalog_definition(catalog_version,item_id,definition) VALUES($1,$2,'{}'::jsonb)", [fixture.version, outside.ids[0]]],
    ["UPDATE reward_operation SET result='{}'::jsonb WHERE operation_id=$1", [input.operationId]],
    ['UPDATE reward_operation SET completed=false WHERE operation_id=$1', [input.operationId]],
    ['DELETE FROM reward_operation WHERE operation_id=$1', [input.operationId]],
    ['UPDATE reward_grant SET already_owned=true WHERE operation_id=$1', [input.operationId]],
    ['DELETE FROM reward_grant WHERE operation_id=$1', [input.operationId]],
    ['INSERT INTO reward_grant(operation_id,item_id,account_id,catalog_version,already_owned) VALUES($1,$2,$3,$4,false)', [input.operationId, fixture.ids[1], accountId, fixture.version]],
  ];
  for (const [sql, params] of attempts) {
    await assert.rejects(pool.query(sql, params), (error: unknown) => (error as { code?: string }).code === '23514', sql);
  }
  assert.deepEqual(await progression.grantEntitlements(input), result);
  assert.deepEqual((await pool.query('SELECT definition FROM catalog_definition WHERE catalog_version=$1 AND item_id=$2', [fixture.version, fixture.items[0].id])).rows[0].definition, fixture.items[0].definition);
});

test('loadout constraints enforce owner, catalog version, owned items and the four accepted styles', async () => {
  const fixture = await catalogFixture();
  await progression.grantEntitlements(grantInput(fixture.version, fixture.ids.slice(0, 2)));
  await progression.grantEntitlements(grantInput(fixture.version, [fixture.ids[2]], otherAccountId));
  const loadoutIds: string[] = [];
  for (const style of ['handling', 'acceleration', 'speed', 'drift']) {
    const id = randomUUID();
    await pool.query('INSERT INTO loadout(id,account_id,catalog_version,style_id) VALUES($1,$2,$3,$4)', [id, accountId, fixture.version, style]);
    loadoutIds.push(id);
  }
  await assert.rejects(pool.query('INSERT INTO loadout(id,account_id,catalog_version,style_id) VALUES($1,$2,$3,$4)', [randomUUID(), accountId, fixture.version, 'balanced']),
    (error: unknown) => (error as { code?: string }).code === '23514');
  const insert = 'INSERT INTO loadout_item(loadout_id,account_id,catalog_version,slot_id,item_id) VALUES($1,$2,$3,$4,$5)';
  await pool.query(insert, [loadoutIds[0], accountId, fixture.version, 'fixture-slot-a', fixture.ids[0]]);
  const foreignKeyViolation = (error: unknown) => (error as { code?: string }).code === '23503';
  await assert.rejects(pool.query(insert, [loadoutIds[0], otherAccountId, fixture.version, 'fixture-wrong-owner', fixture.ids[2]]), foreignKeyViolation);
  await assert.rejects(pool.query(insert, [loadoutIds[0], accountId, fixture.version, 'fixture-unowned', fixture.ids[2]]), foreignKeyViolation);
  const nextVersion = `test-${randomUUID()}`;
  await progression.publishCatalog({ version: nextVersion, items: fixture.items });
  await assert.rejects(pool.query(insert, [loadoutIds[0], accountId, nextVersion, 'fixture-wrong-version', fixture.ids[1]]), foreignKeyViolation);
  const outside = await catalogFixture(1);
  await progression.grantEntitlements(grantInput(outside.version, outside.ids));
  await assert.rejects(pool.query(insert, [loadoutIds[0], accountId, fixture.version, 'fixture-absent-definition', outside.ids[0]]), foreignKeyViolation);
  const updatedLoadout = randomUUID();
  await pool.query('INSERT INTO loadout(id,account_id,catalog_version,style_id) VALUES($1,$2,$3,$4)', [updatedLoadout, accountId, nextVersion, 'drift']);
  await pool.query(insert, [updatedLoadout, accountId, nextVersion, 'fixture-slot-a', fixture.ids[0]]);
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM loadout_item WHERE loadout_id=ANY($1::uuid[])', [[...loadoutIds, updatedLoadout]])).rows[0].total, 2);
});

type Client = { cookie: string; csrfToken: string; user: { id: string; kind: string } };
function clientFrom(response: { cookies: { name: string; value: string }[]; json(): any }): Client {
  const cookie = response.cookies.find((entry) => entry.name === config.cookieName)!;
  return { ...response.json(), cookie: `${cookie.name}=${cookie.value}` };
}
async function post(client: Client, url: string, payload: unknown) {
  return app.inject({
    method: 'POST', url, payload: payload as object,
    headers: { cookie: client.cookie, origin: config.origin, 'x-csrf-token': client.csrfToken },
  });
}

test('guest and authenticated clients cannot publish catalogs, grant inventory or submit local race rewards', async () => {
  const fixture = await catalogFixture(1);
  const guest = clientFrom(await app.inject({ method: 'GET', url: '/api/auth/bootstrap' }));
  const loginGuest = clientFrom(await app.inject({ method: 'GET', url: '/api/auth/bootstrap' }));
  const attempt = (await post(loginGuest, '/api/auth/attempt', { provider: 'dev' })).json();
  const login = await post(loginGuest, '/api/auth/dev', { ...attempt, profileId: 'dev-1' });
  assert.equal(login.statusCode, 200, login.body);
  const account = clientFrom(login);
  assert.equal(guest.user.kind, 'guest');
  assert.equal(account.user.kind, 'account');
  const before = (await pool.query('SELECT count(*)::int AS total FROM reward_operation')).rows[0].total;
  for (const client of [guest, account]) {
    for (const route of ['/api/catalog/publish', '/api/rewards/grant', '/api/account/rewards', '/api/inventory/grant', '/api/progression/grant', '/api/race/results', '/api/account/progress']) {
      const response = await post(client, route, {
        ...grantInput(fixture.version, fixture.ids), localRaceFinished: true, position: 1, shards: 999,
      });
      assert.equal(response.statusCode, 404, `${client.user.kind} ${route}: ${response.body}`);
    }
    const injected = await post(client, '/api/race/ticket', { styleId: 'drift', rewards: fixture.ids, shards: 999 });
    assert.equal(injected.statusCode, 400, injected.body);
  }
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM reward_operation')).rows[0].total, before);
  assert.equal((await pool.query('SELECT count(*)::int AS total FROM inventory_entry WHERE item_id=$1', [fixture.ids[0]])).rows[0].total, 0);
});
