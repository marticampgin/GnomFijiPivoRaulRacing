import { Pool } from 'pg';
import { readConfig } from './config.js';
import { buildApp } from './app.js';

const config = readConfig();
const pool = new Pool({ connectionString: config.databaseUrl, max: 10 });
const app = await buildApp(config, pool);
await app.listen({ host: config.host, port: config.port });
console.log(`GNOM Meta API listening on ${config.origin}`);
let stopping = false;
const stop = async () => {
  if (stopping) return;
  stopping = true;
  await app.close();
  await pool.end();
};
process.once('SIGTERM', stop);
process.once('SIGINT', stop);
