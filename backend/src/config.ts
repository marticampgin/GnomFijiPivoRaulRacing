export type Environment = 'local' | 'test' | 'staging' | 'production';

export interface Config {
  environment: Environment;
  devAuth: boolean;
  databaseUrl: string;
  sessionSecret: string;
  origin: string;
  host: string;
  port: number;
  secureCookie: boolean;
  cookieName: string;
  raceTicketSecret?: string;
  websocketUrl: string;
}

export function readConfig(env: NodeJS.ProcessEnv = process.env): Config {
  const environment = env.DEPLOYMENT_ENV;
  if (!['local', 'test', 'staging', 'production'].includes(environment ?? '')) {
    throw new Error('DEPLOYMENT_ENV must explicitly name local, test, staging or production');
  }
  const local = environment === 'local' || environment === 'test';
  const devAuth = env.DEV_AUTH_ENABLED === 'true';
  if (env.DEV_AUTH_ENABLED && !['true', 'false'].includes(env.DEV_AUTH_ENABLED)) {
    throw new Error('DEV_AUTH_ENABLED must be true or false');
  }
  if (!local && (devAuth || env.IDENTITY_PROVIDER === 'dev')) {
    throw new Error('Dev authentication is forbidden in public environments');
  }
  if (!env.DATABASE_URL || !env.SESSION_SECRET || Buffer.byteLength(env.SESSION_SECRET) < 32) {
    throw new Error('DATABASE_URL and a SESSION_SECRET of at least 32 bytes are required');
  }
  const database = new URL(env.DATABASE_URL);
  if (!['postgres:', 'postgresql:'].includes(database.protocol)) throw new Error('PostgreSQL URL required');
  const port = Number(env.PORT ?? 8787);
  if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid PORT');
  const origin = new URL(env.APP_ORIGIN ?? (local ? `http://127.0.0.1:${port}` : ''));
  const loopback = ['127.0.0.1', 'localhost', '[::1]'].includes(origin.hostname);
  if (origin.origin !== origin.href.replace(/\/$/, '') || origin.username || origin.password) {
    throw new Error('APP_ORIGIN must contain only scheme, host and optional port');
  }
  if (origin.protocol !== 'https:' && !(local && loopback && origin.protocol === 'http:')) {
    throw new Error('HTTPS required outside loopback local/test');
  }
  const host = env.HOST ?? '127.0.0.1';
  if (local && !['127.0.0.1', '::1', 'localhost'].includes(host)) {
    throw new Error('Local/test API must bind to loopback');
  }
  if (env.RACE_TICKET_SECRET && Buffer.byteLength(env.RACE_TICKET_SECRET) < 32) {
    throw new Error('RACE_TICKET_SECRET must be at least 32 bytes');
  }
  const websocketUrl = env.RACE_WEBSOCKET_URL ?? (local ? 'ws://127.0.0.1:9080' : '');
  if (websocketUrl) {
    const websocket = new URL(websocketUrl);
    if (websocket.protocol !== 'wss:' && !(local && ['127.0.0.1', 'localhost', '[::1]'].includes(websocket.hostname) && websocket.protocol === 'ws:')) {
      throw new Error('Secure race WebSocket required outside loopback');
    }
  }
  return {
    environment: environment as Environment, devAuth, databaseUrl: env.DATABASE_URL,
    sessionSecret: env.SESSION_SECRET, origin: origin.origin, host, port,
    secureCookie: origin.protocol === 'https:',
    cookieName: local ? `gnom_${environment}_session` : '__Host-gnom_session',
    raceTicketSecret: env.RACE_TICKET_SECRET, websocketUrl,
  };
}
