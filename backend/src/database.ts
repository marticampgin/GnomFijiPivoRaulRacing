import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { Pool, type PoolClient } from 'pg';
import type { Config } from './config.js';
import { DEV_ISSUER, DEV_PROFILES } from './identity.js';

export async function transaction<T>(pool: Pool, work: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally { client.release(); }
}

export async function migrate(pool: Pool, config: Config): Promise<void> {
  const sql = await readFile(new URL('../migrations/001_auth.sql', import.meta.url), 'utf8');
  await transaction(pool, async (client) => {
    await client.query('SELECT pg_advisory_xact_lock(74189230)');
    await client.query(sql);
    await client.query('INSERT INTO app_environment(environment) VALUES ($1) ON CONFLICT DO NOTHING', [config.environment]);
    const { rows } = await client.query('SELECT environment FROM app_environment');
    if (rows.length !== 1 || rows[0].environment !== config.environment) throw new Error('Database environment mismatch');
    if (config.devAuth) {
      for (const profile of DEV_PROFILES) {
        const existing = await client.query('SELECT account_id FROM account_identity WHERE provider=$1 AND issuer=$2 AND subject=$3', ['dev', DEV_ISSUER, profile.id]);
        if (existing.rowCount) continue;
        const id = randomUUID();
        await client.query('INSERT INTO account(id, display_name) VALUES($1,$2)', [id, profile.displayName]);
        await client.query('INSERT INTO account_identity(provider,issuer,subject,account_id) VALUES($1,$2,$3,$4)', ['dev', DEV_ISSUER, profile.id, id]);
      }
    }
  });
}

export async function assertDatabaseEnvironment(pool: Pool, config: Config): Promise<void> {
  const { rows } = await pool.query('SELECT environment FROM app_environment');
  if (rows.length !== 1 || rows[0].environment !== config.environment) throw new Error('Database environment mismatch');
}
