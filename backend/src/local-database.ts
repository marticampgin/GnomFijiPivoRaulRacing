import { access, mkdir, readFile, writeFile } from 'node:fs/promises';
import { randomBytes } from 'node:crypto';
import { resolve } from 'node:path';
import { bundledPostgresBin, NativePostgres } from './native-postgres.js';

interface LocalDatabaseOptions {
  signal?: AbortSignal;
  onStarted?: (postgres: { stop(): Promise<void> }) => void;
}

export async function startLocalDatabase(directory: string, port = 55432, options: LocalDatabaseOptions = {}) {
  options.signal?.throwIfAborted();
  await mkdir(directory, { recursive: true, mode: 0o700 });
  const passwordFile = resolve(directory, 'password');
  let password: string;
  try { password = await readFile(passwordFile, 'utf8'); }
  catch (error) {
    if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error;
    password = randomBytes(32).toString('hex');
    await writeFile(passwordFile, password, { mode: 0o600, flag: 'wx' });
  }
  const databaseDir = resolve(directory, 'cluster');
  let diagnostic = '';
  const capture = (message: unknown) => { diagnostic = (diagnostic + String(message)).slice(-8000); };
  const nativeBin = process.env.PG_BIN_DIR ?? await bundledPostgresBin();
  const postgres = new NativePostgres({ bin: nativeBin, databaseDir, socketDir: directory, passwordFile, password, port, user: 'gnom_local' });
  let stopping: Promise<void> | undefined;
  const owner = { stop: () => stopping ??= postgres.stop() };
  let started = false;
  try {
    options.signal?.throwIfAborted();
    try { await access(resolve(databaseDir, 'PG_VERSION')); }
    catch {
      // initdb's temporary password file must stay private as well as the cluster.
      const previousMask = process.umask(0o077);
      try { await postgres.initialise(options.signal); }
      finally { process.umask(previousMask); }
    }
    options.signal?.throwIfAborted();
    await postgres.start(options.signal);
    started = true;
    options.onStarted?.(owner);
    options.signal?.throwIfAborted();
    const client = postgres.getPgClient('postgres', '127.0.0.1');
    client.on('error', capture);
    try {
      await client.connect();
      const result = await client.query("SELECT 1 FROM pg_database WHERE datname='gnom_local'");
      if (!result.rowCount) await postgres.createDatabase('gnom_local');
    } finally { await client.end(); }
    options.signal?.throwIfAborted();
  } catch (error) {
    if (started) await owner.stop();
    throw new Error(`Local PostgreSQL failed: ${error instanceof Error ? error.message : 'startup failure'}\n${diagnostic}`, { cause: error });
  }
  return { postgres: owner, databaseUrl: `postgresql://gnom_local:${password}@127.0.0.1:${port}/gnom_local` };
}
