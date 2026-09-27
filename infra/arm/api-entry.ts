import { Pool } from 'pg';
import { readConfig } from '../../backend/src/config.js';
import { migrate } from '../../backend/src/database.js';
import { buildApp } from '../../backend/src/app.js';

if (process.platform !== 'linux' || process.arch !== 'arm64') throw new Error('Native Linux ARM64 stand required');
const config = readConfig();
if (config.environment !== 'test' || config.host !== '127.0.0.1') throw new Error('Stand must remain isolated test/loopback');
const pool = new Pool({ connectionString: config.databaseUrl, max: 10 });
try {
  await migrate(pool, config);
  const app = await buildApp(config, pool, { staticRoot: '/app' });
  await app.listen({ host: config.host, port: config.port });
  console.log('GNOM ARM test API ready on loopback');
  let stopping = false;
  const stop = async () => {
    if (stopping) return;
    stopping = true;
    await app.close();
    await pool.end();
  };
  process.once('SIGTERM', stop);
  process.once('SIGINT', stop);
} catch (error) {
  await pool.end();
  throw error;
}
