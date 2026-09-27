import { createHash, createHmac, randomBytes, randomUUID, timingSafeEqual } from 'node:crypto';
import type { Pool, PoolClient } from 'pg';
import type { Config } from './config.js';
import { transaction } from './database.js';
import { DEV_PROFILES, DevIdentityProvider } from './identity.js';
import { loadTrackManifest, raceCompatibility, STYLE_IDS, TICKET_VERSION, type StyleId, type TrackManifest } from './race-compatibility.js';

export class AuthError extends Error {
  constructor(public statusCode: number, public code: string) { super(code); }
}

export interface Session {
  token_hash: string;
  account_id: string | null;
  guest_id: string | null;
  pending_guest_id: string | null;
  provider: 'dev' | 'google' | null;
  environment: string;
  revoked_at: Date | null;
  expires_at: Date;
}

const hash = (value: string) => createHash('sha256').update(value).digest('hex');
export const equal = (left: string, right: string) => {
  const a = Buffer.from(left), b = Buffer.from(right);
  return a.length === b.length && timingSafeEqual(a, b);
};
const secret = () => randomBytes(32).toString('base64url');

export class AuthService {
  private devProvider: DevIdentityProvider | null;
  private trackManifest: TrackManifest | null;
  constructor(readonly pool: Pool, readonly config: Config) {
    if (config.devAuth && !['local', 'test'].includes(config.environment)) throw new Error('Dev authentication is forbidden in public environments');
    this.devProvider = config.devAuth ? new DevIdentityProvider() : null;
    this.trackManifest = config.raceTicketSecret && config.websocketUrl ? loadTrackManifest(config.trackManifestPath) : null;
  }

  tokenHash(token: string): string {
    return createHmac('sha256', this.config.sessionSecret).update(`${this.config.environment}:session:${token}`).digest('hex');
  }
  csrf(token: string): string {
    return createHmac('sha256', this.config.sessionSecret).update(`${this.config.environment}:csrf:${token}`).digest('base64url');
  }
  private validateSession(session: Session | undefined): Session {
    if (!session || session.revoked_at || session.expires_at.getTime() <= Date.now() || session.environment !== this.config.environment) {
      throw new AuthError(401, 'session_required');
    }
    if (session.provider === 'dev' && (!this.config.devAuth || !['local', 'test'].includes(this.config.environment))) {
      throw new AuthError(401, 'session_required');
    }
    return session;
  }
  async session(token: string | undefined, client: Pool | PoolClient = this.pool, lock = false): Promise<Session> {
    if (!token || !/^[A-Za-z0-9_-]{43}$/.test(token)) throw new AuthError(401, 'session_required');
    const { rows } = await client.query('SELECT * FROM game_session WHERE token_hash=$1' + (lock ? ' FOR UPDATE' : ''), [this.tokenHash(token)]);
    return this.validateSession(rows[0]);
  }
  private async issue(client: PoolClient, principal: { accountId?: string; guestId?: string; pendingGuestId?: string | null; provider?: string }): Promise<string> {
    const token = secret();
    await client.query(`INSERT INTO game_session(token_hash,environment,account_id,guest_id,pending_guest_id,provider,expires_at)
      VALUES($1,$2,$3,$4,$5,$6,now()+interval '7 days')`, [this.tokenHash(token), this.config.environment, principal.accountId ?? null, principal.guestId ?? null, principal.pendingGuestId ?? null, principal.provider ?? null]);
    return token;
  }
  private async newGuest(client: PoolClient): Promise<string> {
    const guestId = randomUUID();
    await client.query('INSERT INTO guest_profile(id) VALUES($1)', [guestId]);
    return this.issue(client, { guestId });
  }
  async guest(): Promise<string> { return transaction(this.pool, (client) => this.newGuest(client)); }

  async bootstrap(token: string) {
    const session = await this.session(token);
    const account = session.account_id
      ? (await this.pool.query('SELECT display_name,practice_finishes FROM account WHERE id=$1', [session.account_id])).rows[0]
      : (await this.pool.query('SELECT practice_finishes FROM guest_profile WHERE id=$1', [session.guest_id])).rows[0];
    const pending = session.pending_guest_id
      ? (await this.pool.query('SELECT merged_account_id FROM guest_profile WHERE id=$1', [session.pending_guest_id])).rows[0]
      : null;
    return {
      csrfToken: this.csrf(token),
      user: { kind: session.account_id ? 'account' : 'guest', id: session.account_id ?? session.guest_id, displayName: account.display_name ?? 'Guest' },
      devProfiles: this.config.devAuth ? DEV_PROFILES : [],
      mergeAvailable: Boolean(pending && !pending.merged_account_id),
      progress: { practiceFinishes: account.practice_finishes },
    };
  }

  async attempt(token: string): Promise<{ attemptId: string; nonce: string }> {
    if (!this.devProvider) throw new AuthError(404, 'not_found');
    return transaction(this.pool, async (client) => {
      const session = await this.session(token, client, true);
      const attemptId = randomUUID(), nonce = secret();
      // One active attempt per browser prevents stale tabs from replaying an earlier choice.
      await client.query('UPDATE auth_attempt SET consumed_at=now() WHERE session_hash=$1 AND consumed_at IS NULL', [session.token_hash]);
      await client.query(`INSERT INTO auth_attempt(id,session_hash,provider,nonce_hash,expires_at)
        VALUES($1,$2,'dev',$3,now()+interval '5 minutes')`, [attemptId, session.token_hash, hash(nonce)]);
      return { attemptId, nonce };
    });
  }

  async login(token: string, proof: { profileId: string; attemptId: string; nonce: string }): Promise<string> {
    if (!this.devProvider) throw new AuthError(404, 'not_found');
    const identity = await this.devProvider.verify(proof).catch(() => { throw new AuthError(400, 'invalid_profile'); });
    return transaction(this.pool, async (client) => {
      const session = await this.session(token, client, true);
      const { rows } = await client.query('SELECT * FROM auth_attempt WHERE id=$1 FOR UPDATE', [proof.attemptId]);
      const attempt = rows[0];
      if (!attempt || attempt.session_hash !== session.token_hash || attempt.provider !== identity.provider || attempt.consumed_at || attempt.expires_at.getTime() <= Date.now() || !equal(attempt.nonce_hash, hash(proof.nonce))) {
        throw new AuthError(401, 'invalid_attempt');
      }
      const identityRow = (await client.query('SELECT account_id FROM account_identity WHERE provider=$1 AND issuer=$2 AND subject=$3', [identity.provider, identity.issuer, identity.subject])).rows[0];
      if (!identityRow) throw new AuthError(401, 'invalid_profile');
      await client.query('UPDATE auth_attempt SET consumed_at=now() WHERE id=$1', [proof.attemptId]);
      await client.query('UPDATE game_session SET revoked_at=now() WHERE token_hash=$1', [session.token_hash]);
      return this.issue(client, { accountId: identityRow.account_id, provider: identity.provider, pendingGuestId: session.guest_id ?? session.pending_guest_id });
    });
  }

  async logout(token: string): Promise<string> {
    return transaction(this.pool, async (client) => {
      const session = await this.session(token, client, true);
      await client.query('UPDATE game_session SET revoked_at=now() WHERE token_hash=$1', [session.token_hash]);
      await client.query('UPDATE auth_attempt SET consumed_at=now() WHERE session_hash=$1 AND consumed_at IS NULL', [session.token_hash]);
      // Unmerged guest progress remains owned by this browser after logout.
      const guestId = session.guest_id ?? session.pending_guest_id;
      if (guestId) {
        const guest = (await client.query('SELECT merged_account_id FROM guest_profile WHERE id=$1', [guestId])).rows[0];
        if (guest && !guest.merged_account_id) return this.issue(client, { guestId });
      }
      return this.newGuest(client);
    });
  }

  async merge(token: string, input: { targetAccountId: string; confirmed: boolean; mergeId: string }) {
    return transaction(this.pool, async (client) => {
      const session = await this.session(token, client, true);
      if (!session.account_id) throw new AuthError(403, 'account_required');
      if (!input.confirmed || input.targetAccountId !== session.account_id || !session.pending_guest_id) throw new AuthError(403, 'merge_not_authorized');
      const guest = (await client.query('SELECT * FROM guest_profile WHERE id=$1 FOR UPDATE', [session.pending_guest_id])).rows[0];
      const existingKey = (await client.query('SELECT * FROM guest_merge WHERE merge_id=$1', [input.mergeId])).rows[0];
      if (existingKey && (existingKey.guest_id !== guest.id || existingKey.account_id !== session.account_id)) throw new AuthError(409, 'merge_key_conflict');
      if (guest.merged_account_id && guest.merged_account_id !== session.account_id) throw new AuthError(409, 'guest_already_merged');
      if (!guest.merged_account_id) {
        await client.query('UPDATE account SET practice_finishes=practice_finishes+$1 WHERE id=$2', [guest.practice_finishes, session.account_id]);
        await client.query('INSERT INTO guest_merge(merge_id,guest_id,account_id,practice_finishes) VALUES($1,$2,$3,$4)', [input.mergeId, guest.id, session.account_id, guest.practice_finishes]);
        await client.query('UPDATE guest_profile SET merged_account_id=$1 WHERE id=$2', [session.account_id, guest.id]);
      }
      const account = (await client.query('SELECT practice_finishes FROM account WHERE id=$1', [session.account_id])).rows[0];
      return { merged: true, progress: { practiceFinishes: account.practice_finishes } };
    });
  }

  async ticket(token: string, styleId: StyleId = 'handling') {
    if (!STYLE_IDS.includes(styleId)) throw new AuthError(400, 'invalid_request');
    if (!this.config.raceTicketSecret || !this.config.websocketUrl || !this.trackManifest) throw new AuthError(503, 'race_unavailable');
    const profile = await this.bootstrap(token);
    const compatibility = raceCompatibility(this.trackManifest);
    const payload = {
      v: TICKET_VERSION, match_id: 'prototype-1', player_id: profile.user.id, display_name: profile.user.displayName, style_id: styleId,
      ...compatibility, expires_at: Math.floor(Date.now() / 1000) + 60, jti: randomUUID(),
    };
    const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const signature = createHmac('sha256', this.config.raceTicketSecret).update(body).digest('base64url');
    return { ticket: `${body}.${signature}`, websocketUrl: this.config.websocketUrl, matchId: payload.match_id, playerId: payload.player_id, styleId, compatibility, track: this.trackManifest };
  }
}
