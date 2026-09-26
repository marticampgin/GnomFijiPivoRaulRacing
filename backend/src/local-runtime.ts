import { randomBytes } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { Pool } from 'pg';
import { startLocalDatabase } from './local-database.js';
import { readConfig } from './config.js';
import { migrate } from './database.js';
import { buildApp } from './app.js';
import { withLocalShutdown } from './local-lifecycle.js';

await withLocalShutdown(async (lifecycle) => {
  if (process.env.DEPLOYMENT_ENV && process.env.DEPLOYMENT_ENV !== 'local') throw new Error('Local launcher only supports DEPLOYMENT_ENV=local');
  console.log('GNOM local: starting isolated PostgreSQL');
  const local = await startLocalDatabase(fileURLToPath(new URL('../.local/', import.meta.url)), Number(process.env.LOCAL_PG_PORT ?? 55432), {
    signal: lifecycle.signal,
    onStarted: (postgres) => lifecycle.own(() => postgres.stop()),
  });
  lifecycle.checkpoint();
  console.log('GNOM local: PostgreSQL ready, applying schema');
  const config = readConfig({ ...process.env, DEPLOYMENT_ENV: 'local', DEV_AUTH_ENABLED: 'true', DATABASE_URL: local.databaseUrl, SESSION_SECRET: process.env.SESSION_SECRET ?? randomBytes(32).toString('hex') });
  const pool = new Pool({ connectionString: config.databaseUrl, max: 10 });
  lifecycle.own(() => pool.end());
  await migrate(pool, config);
  lifecycle.checkpoint();
  const app = await buildApp(config, pool);
  lifecycle.own(() => app.close());
  lifecycle.checkpoint();
  console.log('GNOM local: schema ready, starting HTTP API');
  await app.listen({ host: config.host, port: config.port });
  lifecycle.checkpoint();
  console.log(`GNOM local API + PostgreSQL: ${config.origin}`);
});
