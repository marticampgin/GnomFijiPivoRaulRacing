import { execFile, spawn, type ChildProcess } from 'node:child_process';
import { promisify } from 'node:util';
import { dirname, resolve } from 'node:path';
import { Client } from 'pg';

const execute = promisify(execFile);

async function stopChild(child: ChildProcess, exited: Promise<void>): Promise<void> {
  if (child.exitCode === null && child.signalCode === null) child.kill('SIGINT');
  const force = setTimeout(() => {
    if (child.exitCode === null && child.signalCode === null) child.kill('SIGKILL');
  }, 5000);
  try { await exited; }
  finally { clearTimeout(force); }
}

export async function bundledPostgresBin(): Promise<string> {
  const supported: Record<string, string[]> = { darwin: ['arm64', 'x64'], linux: ['arm', 'arm64', 'ia32', 'ppc64', 'x64'] };
  if (!supported[process.platform]?.includes(process.arch)) throw new Error('Local PostgreSQL requires a supported macOS/Linux runtime or PG_BIN_DIR');
  const binaries = await import(`@embedded-postgres/${process.platform}-${process.arch}`) as { postgres: string };
  return dirname(binaries.postgres);
}

export class NativePostgres {
  private child?: ChildProcess;
  private exited?: Promise<void>;
  private stopping?: Promise<void>;
  constructor(private options: { bin: string; databaseDir: string; socketDir: string; passwordFile: string; password: string; port: number; user: string }) {}

  async initialise(signal?: AbortSignal): Promise<void> {
    const o = this.options;
    signal?.throwIfAborted();
    const initialising = execute(resolve(o.bin, 'initdb'), ['-D', o.databaseDir, '-U', o.user, '--auth=scram-sha-256', `--pwfile=${o.passwordFile}`, '--encoding=UTF8', '--locale=C'], { timeout: 120000, signal, killSignal: 'SIGINT' });
    const exited = new Promise<void>((done) => initialising.child.once('close', () => done()));
    try { await initialising; }
    catch (error) { await stopChild(initialising.child, exited); throw error; }
  }
  async start(signal?: AbortSignal): Promise<void> {
    signal?.throwIfAborted();
    const o = this.options;
    const child = spawn(resolve(o.bin, 'postgres'), ['-D', o.databaseDir, '-p', String(o.port), '-h', '127.0.0.1', '-k', o.socketDir], { env: { ...process.env, LC_MESSAGES: 'C' }, stdio: ['ignore', 'ignore', 'pipe'] });
    this.child = child;
    this.exited = new Promise((done) => child.once('close', () => done()));
    let abort: (() => void) | undefined;
    let timeout: NodeJS.Timeout | undefined;
    try {
      await new Promise<void>((done, fail) => {
        let output = '';
        abort = () => fail(signal!.reason);
        signal?.addEventListener('abort', abort, { once: true });
        timeout = setTimeout(() => fail(new Error(`PostgreSQL startup timed out: ${output}`)), 30000);
        child.stderr!.on('data', (chunk: Buffer) => {
          output = (output + chunk.toString()).slice(-4000);
          if (output.includes('database system is ready to accept connections')) done();
        });
        child.once('error', fail);
        child.once('exit', (code, exitSignal) => fail(new Error(`PostgreSQL exited (${code ?? exitSignal}): ${output}`)));
      });
    } catch (error) {
      await this.stop();
      throw error;
    } finally {
      clearTimeout(timeout);
      if (abort) signal?.removeEventListener('abort', abort);
    }
  }
  stop(): Promise<void> {
    return this.stopping ??= (async () => {
      const child = this.child;
      if (!child) return;
      try { await stopChild(child, this.exited!); }
      finally { this.child = undefined; }
    })();
  }
  getPgClient(database = 'postgres', host = '127.0.0.1'): Client {
    return new Client({ host, port: this.options.port, user: this.options.user, password: this.options.password, database });
  }
  async createDatabase(name: string): Promise<void> {
    if (!/^[a-z_][a-z0-9_]*$/.test(name)) throw new Error('Invalid local database name');
    const client = this.getPgClient();
    await client.connect();
    try { await client.query(`CREATE DATABASE "${name}"`); }
    finally { await client.end(); }
  }
}
