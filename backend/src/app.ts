import { access } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import Fastify, { type FastifyError, type FastifyReply, type FastifyRequest } from 'fastify';
import cookie from '@fastify/cookie';
import rateLimit from '@fastify/rate-limit';
import staticFiles from '@fastify/static';
import type { Pool } from 'pg';
import type { Config } from './config.js';
import { assertDatabaseEnvironment } from './database.js';
import { AuthError, AuthService, equal } from './auth.js';
import { STYLE_IDS, type StyleId } from './race-compatibility.js';

const uuid = { type: 'string', format: 'uuid' };
const empty = { type: 'object', additionalProperties: false, properties: {} };
const body = (properties: object, required: string[]) => ({ type: 'object', additionalProperties: false, properties, required });

export async function buildApp(config: Config, pool: Pool, options: { staticRoot?: string | false } = {}) {
  await assertDatabaseEnvironment(pool, config);
  const auth = new AuthService(pool, config);
  const app = Fastify({ logger: false, bodyLimit: 8192, trustProxy: false, ajv: { customOptions: { removeAdditional: false, coerceTypes: false } } });
  await app.register(cookie);
  await app.register(rateLimit, { global: true, max: 300, timeWindow: '1 minute' });
  app.setErrorHandler((error, _request, reply) => {
    if (error instanceof AuthError) return reply.code(error.statusCode).send({ error: error.code });
    if ((error as FastifyError).validation) return reply.code(400).send({ error: 'invalid_request' });
    if ((error as FastifyError).statusCode === 429) return reply.code(429).send({ error: 'rate_limited' });
    const status = (error as FastifyError).statusCode;
    if (status && status >= 400 && status < 500) return reply.code(status).send({ error: 'request_rejected' });
    return reply.code(500).send({ error: 'internal_error' });
  });
  app.addHook('onSend', async (request, reply, payload) => {
    reply.header('X-Content-Type-Options', 'nosniff');
    reply.header('Referrer-Policy', 'same-origin');
    if (request.url.startsWith('/api/')) reply.header('Cache-Control', 'no-store');
    return payload;
  });
  const token = (request: FastifyRequest) => request.cookies[config.cookieName];
  const setSession = (reply: FastifyReply, value: string) => reply.setCookie(config.cookieName, value, {
    httpOnly: true, secure: config.secureCookie, sameSite: 'lax', path: '/', maxAge: 7 * 24 * 60 * 60,
  });
  const protect = async (request: FastifyRequest) => {
    if (request.headers.origin !== config.origin) throw new AuthError(403, 'origin_rejected');
    const sessionToken = token(request);
    await auth.session(sessionToken);
    const csrf = request.headers['x-csrf-token'];
    if (typeof csrf !== 'string' || !equal(csrf, auth.csrf(sessionToken!))) throw new AuthError(403, 'csrf_rejected');
  };
  app.get('/api/health', async () => ({ status: 'ok', environment: config.environment }));
  app.get('/api/auth/bootstrap', async (request, reply) => {
    // Reject cross-origin bootstrap so embedded pages cannot churn anonymous profiles.
    if (request.headers['sec-fetch-site'] === 'cross-site' || (request.headers.origin && request.headers.origin !== config.origin)) {
      throw new AuthError(403, 'origin_rejected');
    }
    let current = token(request);
    try { await auth.session(current); }
    catch (error) {
      if (!(error instanceof AuthError)) throw error;
      current = await auth.guest();
      setSession(reply, current);
    }
    return auth.bootstrap(current!);
  });
  app.get('/api/me', async (request) => auth.bootstrap(token(request) ?? ''));
  app.get('/api/account/progress', async (request) => {
    const session = await auth.session(token(request));
    if (!session.account_id) throw new AuthError(403, 'account_required');
    return (await auth.bootstrap(token(request)!)).progress;
  });
  if (config.devAuth) {
    app.post('/api/auth/attempt', { preHandler: protect, schema: { body: body({ provider: { const: 'dev', type: 'string' } }, ['provider']) } }, async (request) => auth.attempt(token(request)!));
    app.post<{ Body: { profileId: string; attemptId: string; nonce: string } }>('/api/auth/dev', {
      preHandler: protect,
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } },
      schema: { body: body({ profileId: { type: 'string', maxLength: 32 }, attemptId: uuid, nonce: { type: 'string', minLength: 43, maxLength: 43 } }, ['profileId', 'attemptId', 'nonce']) },
    }, async (request, reply) => {
      const fresh = await auth.login(token(request)!, request.body);
      setSession(reply, fresh);
      return auth.bootstrap(fresh);
    });
  }
  app.post('/api/auth/logout', { preHandler: protect, schema: { body: empty } }, async (request, reply) => {
    const fresh = await auth.logout(token(request)!);
    setSession(reply, fresh);
    return auth.bootstrap(fresh);
  });
  app.post<{ Body: { targetAccountId: string; confirmed: boolean; mergeId: string } }>('/api/guest/merge', {
    preHandler: protect,
    schema: { body: body({ targetAccountId: uuid, confirmed: { type: 'boolean' }, mergeId: uuid }, ['targetAccountId', 'confirmed', 'mergeId']) },
  }, async (request) => auth.merge(token(request)!, request.body));
  app.post<{ Body: { styleId?: StyleId } }>('/api/race/ticket', {
    preHandler: protect,
    schema: { body: body({ styleId: { type: 'string', enum: STYLE_IDS } }, []) },
  }, async (request) => auth.ticket(token(request)!, request.body.styleId));

  if (options.staticRoot !== false) {
    const root = options.staticRoot ?? fileURLToPath(new URL('../../', import.meta.url));
    const build = resolve(root, 'build/web'), web = resolve(root, 'web');
    await app.register(staticFiles, { root: build, serve: false });
    app.get('/', async (_request, reply) => {
      try { await access(resolve(build, 'index.html')); }
      catch { return reply.code(503).type('text/plain').send('Web build missing. Run the project Web export first.'); }
      return reply.sendFile('index.html', build);
    });
    app.get<{ Params: { filename: string } }>('/:filename', async (request, reply) => {
      const filename = request.params.filename;
      if (['app.js', 'app.css', 'track-map.js', 'local-race.js', 'local-race.css', 'race-lobby.js', 'race-lobby.css', 'ui-theme.css', 'race-overlays.css', 'control-settings.js', 'control-settings.css', 'menu-navigation.js'].includes(filename)) return reply.sendFile(filename, web);
      if (/^index\.(js|wasm|pck|png|icon\.png|apple-touch-icon\.png|audio\.worklet\.js|audio\.position\.worklet\.js)$/.test(filename)) return reply.sendFile(filename, build);
      return reply.code(404).send({ error: 'not_found' });
    });
    await app.register(staticFiles, { root: resolve(web, 'assets'), prefix: '/assets/', decorateReply: false, index: false, dotfiles: 'deny' });
  }
  return app;
}
