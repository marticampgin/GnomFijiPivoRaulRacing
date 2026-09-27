# Prototype Meta API

Fastify + TypeScript, Node.js 24 LTS and PostgreSQL. This implements the local/test identity adapter, real server-side sessions and the persistent catalog/inventory foundation. Google verification is deliberately not implemented yet; `IdentityProvider` is the boundary for that later adapter. This is not a public deployment or a payment service.

## Local Run

From the repository root with Node.js 24 on `PATH`:

```sh
npm --prefix backend ci
npm --prefix backend run dev
```

The local launcher starts a real PostgreSQL 18.4 process using the platform binaries installed by the pinned `embedded-postgres` development dependency. It resolves their public `@embedded-postgres/<platform>-<arch>` exports and manages the native child directly so startup is cancellable. It does not install a global database service or create OS users. The cluster and generated database password live in ignored `backend/.local/`; both API and database listen on loopback. API defaults to `http://127.0.0.1:8787`, PostgreSQL to port 55432. `PORT` and `LOCAL_PG_PORT` can override occupied ports. The API's `APP_ORIGIN` must match the browser origin exactly.

`npm run build` bundles the runtime and tests with esbuild into ignored `backend/dist/`. This avoids slow per-file imports in restricted development environments. `npm run dev` builds automatically; a coordinator can build once and launch `node backend/dist/local.mjs`. Startup logs distinguish loading, PostgreSQL initialization, migration and HTTP listening.

### Optional macOS ARM64 Cache

On the current development machine, executables under the Documents workspace stalled on file reads while the same verified binaries ran normally under `/private/tmp`. This is a host-specific workaround, not a requirement or a changed PostgreSQL backend. `PG_BIN_DIR` selects existing trusted native PostgreSQL tools; it does not change authentication or database isolation. Run the following from the repository root when that workaround is needed:

```sh
set -e
runtime="$(mktemp -d /private/tmp/gnom-postgres-runtime.XXXXXX)"
npm pack @embedded-postgres/darwin-arm64@18.4.0-beta.17 --pack-destination "$runtime" --silent
(
  cd "$runtime"
  printf '%s  %s\n' '2a0d5930d173915209b3783857651811ce57d34e649bdac68a7c45047f11d6c394d916e5bf3e29b7651ff773eef11936ef751ef4721dadb30fa6052ac23522d1' 'embedded-postgres-darwin-arm64-18.4.0-beta.17.tgz' | shasum -a 512 -c
)
tar -xzf "$runtime/embedded-postgres-darwin-arm64-18.4.0-beta.17.tgz" -C "$runtime" --strip-components 1
(
  cd "$runtime"
  node scripts/hydrate-symlinks.js
)
export PG_BIN_DIR="$runtime/native/bin"
npm --prefix backend run dev
```

Stop if the checksum check fails; the SHA-512 above is the locked npm artifact's integrity value. The hydration script is that package's standard symlink restoration, not binary modification. No signature, Gatekeeper or quarantine settings are changed. The same `PG_BIN_DIR` works with the test command below. Keep the temporary runtime while the local stand is in use; re-create it if the OS removes it. Production uses `DATABASE_URL` and never starts this development database helper.

If the workspace also exposes dataless JavaScript or Web build files, materialize the selected stand files into a temporary directory with the same relative layout before launch: `backend/dist/`, `backend/migrations/`, `build/web/` and `web/`. A plain `cp` worked on this host. `node_modules/` is not needed by the bundled API when `PG_BIN_DIR` is supplied. Database files then live under that temporary stand's `backend/.local/`; they are separate from the normal local cluster. Do not remove that stand while it is running.

The root page serves `build/web/index.html`, exported by Godot. `web/app.js`, `web/app.css` and `web/assets/` are the only additional public source assets. A missing export returns 503, not a directory listing. SIGINT/SIGTERM cancels startup and closes acquired API, pool and PostgreSQL resources; configuration failures also close the database. Native PostgreSQL receives fast shutdown (`SIGINT`), with a five-second forced-stop fallback for an unresponsive owned child. Profiles persist across local restarts; the default session secret rotates, so browsers sign in again. Set a private `SESSION_SECRET` of at least 32 bytes to keep local sessions across restarts.

The complete project launcher should also generate a private shared `RACE_TICKET_SECRET` of at least 32 bytes for API and Godot worker. This secret is never sent to the client. Without it, ticket requests return 503. `RACE_WEBSOCKET_URL` defaults to `ws://127.0.0.1:9080` only for local/test. The prototype match is `prototype-1`; this is not a rated public allocator.

When racing is enabled, startup loads the generated `shared/track-manifest.json` beside the backend directory. `RACE_TRACK_MANIFEST_PATH` can select an explicit server-owned versioned package. Missing or malformed manifests fail startup rather than issuing tickets for a guessed route. Include this file in temporary stand copies and deployments, and deploy it together with the matching Godot bake/Web export. The API never accepts a client-selected hash. Tickets and launch responses bind wire version 2, vehicle-state schema 1, track schema 1 and `prototype-v3` vehicle simulation separately; an art revision alone does not change simulation compatibility. The v3 collider has chamfered edges at the same external dimensions; v2 sharp-box clients must update together with the worker.

## HTTP Contract

All mutating requests require the session cookie, exact `Origin`, `Content-Type: application/json` and `X-CSRF-Token` returned by bootstrap. Unknown body properties are rejected, and no CORS origins are enabled.

| Method / Route | Request / Result |
| --- | --- |
| `GET /api/auth/bootstrap` | Creates or restores a guest/session; returns `csrfToken`, `user`, `devProfiles`, `mergeAvailable`, `progress`. |
| `POST /api/auth/attempt` | `{provider:"dev"}` returns `{attemptId,nonce}`; local/test with enabled dev adapter only. |
| `POST /api/auth/dev` | `{profileId,attemptId,nonce}` signs into one of `dev-1`, `dev-2`, `dev-3`; rotates session and returns the bootstrap shape. |
| `GET /api/me` | Current bootstrap shape, or 401 for an invalid/revoked/expired session. |
| `GET /api/account/progress` | Account-only probe; guests get 403. |
| `POST /api/auth/logout` | `{}` revokes current session, invalidates pending attempts, returns a guest bootstrap. Unmerged guest progress is preserved. |
| `POST /api/guest/merge` | `{targetAccountId,confirmed:true,mergeId:UUID}` transfers server-held guest progress once; returns `{merged:true,progress}`. |
| `POST /api/race/ticket` | `{}` returns `{ticket,websocketUrl,matchId,playerId,compatibility,track}` for guest practice or an account; expires in 60 seconds. `compatibility` contains the signed simulation identity and schemas; `track` is the generated compact route/minimap descriptor. |

`user` is `{kind:"guest"|"account",id,displayName}`. `progress` currently contains only `practiceFinishes`; no browser endpoint awards progress, currency or inventory. Tests create verified progress fixtures directly in their isolated database. Future authoritative result handling must own actual rewards. Login never merges progress automatically; the browser must separately name and confirm the target account. Sending a guest ID is not ownership proof and is rejected.

## Persistent Data Foundation

`migrate(pool, config)` applies the checked-in SQL files in order under one advisory transaction lock. `schema_migration` records each filename and SHA-256 checksum; changed applied SQL or an unknown newer migration fails rather than silently rewriting history. Add a new migration for later changes. Existing local databases with only `001_auth.sql` are adopted in place: that idempotent migration runs once more before history is recorded. Accounts, sessions and guest progress are preserved. All migrations, the environment check and dev-profile seeding commit together or roll back together.

`ProgressionService` is an internal backend module, not an HTTP API:

- `publishCatalog({version, items: [{id, kind, definition}]})` publishes one immutable version atomically. Stable item IDs retain their kind across versions. Repeating identical content is harmless; changing an existing version is rejected. Definitions are bounded JSON metadata, not approved vehicle stats or a simulation contract.
- `grantEntitlements({operationId, accountId, catalogVersion, source, items})` atomically records the operation, its grants and ownership. The operation ID must identify one trusted server event and be reused on delivery retries. A replay returns the original result, including the original `alreadyOwned` flags; changing its payload is a conflict. Concurrent grants to one account are serialized.
- Inventory records durable, non-stackable rights to `vehicle`, `character`, `part` or `cosmetic` IDs across catalog versions. Another trusted event granting an already-owned right records that fact without creating a second ownership row. This is not a paid-drop duplicate/compensation policy. Currency, consumables, progression levels, purchases and revocation/compensation workflows are outside this stage.
- Loadout tables pin a catalog version and one of the four styles. Composite foreign keys require every equipped item to exist in that version and belong to that same account. Slot IDs remain technical placeholders; compatibility rules, numeric balance, garage editing and signed personal assemblies are not implemented.

No production catalog or starter grants are seeded. No route accepts browser rewards, local results, shard counts or arbitrary inventory writes. Race shards remain transient Godot state. The existing guest merge still transfers only the server-held `practiceFinishes` probe, not this inventory. The race ticket's global `prototype-v13` compatibility marker is unchanged and is not a personal loadout signature.

The journal and published catalog reject ordinary SQL edits/deletions as well as service-level rewrites. This protects application invariants, not a database superuser: deployment roles, backup/recovery and audited compensation operations remain separate work. SQL uses foreign keys and explicit supporting indexes; see [PostgreSQL constraints](https://www.postgresql.org/docs/current/ddl-constraints.html).

## Isolation And Security

- Dev authentication requires both `DEPLOYMENT_ENV=local|test` and `DEV_AUTH_ENABLED=true`. `NODE_ENV` does not enable it.
- `production` and `staging` reject a dev flag or `IDENTITY_PROVIDER=dev` before startup. There are no dev/attempt endpoints when disabled, and the bootstrap publishes no dev profile options.
- Public session verification rejects `provider=dev`, even if a development session row is copied into a correctly marked public database.
- The `app_environment` singleton must exactly match the configured environment. Session hashes and CSRF derive from an environment-scoped secret. Production must use its own database and secret, not just change the local marker.
- Session cookies are opaque, HttpOnly, SameSite=Lax, rotated at login/logout, expire in seven days and can be revoked server-side. Public cookies additionally use Secure and the `__Host-` prefix. Only a hash is stored in SQL.
- Attempts expire after five minutes and are bound to a session, provider and nonce. PostgreSQL row locks make consumption and rotation atomic. Merge has a unique source guest, request key and transactional counter update.
- Auth responses are `no-store`; application request logging is disabled to avoid credential leakage. Rate limiting applies per direct remote IP; do not enable untrusted proxy forwarding.
- No Google credential, balance, role, account ID or external subject is accepted by the dev provider. The three dev fixtures have no purchased items or extra currency.

For a configured non-local deployment, `npm start` requires an already migrated database, explicit `DEPLOYMENT_ENV`, `DATABASE_URL`, `SESSION_SECRET`, HTTPS `APP_ORIGIN` and the appropriate secure race endpoint. The local migration helper is intentionally not exposed as a public HTTP route. This scaffold still needs production migrations/deployment automation, Google integration, session cleanup, observability and operational hardening before public release.

## Verification

```sh
npm --prefix backend run check
npm --prefix backend test
npm --prefix backend audit --omit=dev
```

Tests use real temporary PostgreSQL clusters, ephemeral loopback ports and Fastify injection. Coverage includes cookie flags, session hashing/rotation/revocation/expiry, Origin/CSRF, profile whitelist and extra fields, nonce ownership/expiry/replay, concurrent login, confirmed/idempotent concurrent merge, environment isolation, disabled/public dev routes, copied dev sessions and signed race tickets. Lifecycle coverage includes configuration failures, interrupted acquisition/query/listen, repeated signals, cleanup failures, default binary resolution and native PostgreSQL/initdb cancellation. Temporary test clusters are stopped and removed after successful checks. Native Linux ARM64 runtime capacity is a separate check, not implied by these macOS tests.

Verified on 2026-09-26 with Node.js 24.19.0 and PostgreSQL 18.4 on macOS: 22 tests passed (11 authentication integration tests and 11 lifecycle tests), with a clean TypeScript check and bundle build. Real database checks used the materialized bundle/SQL and `PG_BIN_DIR` workaround; default platform-package binary resolution was also verified. The runtime's reported build string was x86_64 Darwin, so this is not evidence of Linux ARM64 compatibility or capacity.

Reverified on 2026-09-27 after authored-track compatibility: 27 tests passed (12 authentication, 11 lifecycle and 4 manifest tests). Manifest tests compare the API descriptor with the actual Godot bake; ticket tests verify the signed fields and launch descriptor agree. This does not replace the separate Godot/socket/Web integration checks or establish ARM capacity.

Persistent-data stage, 2026-09-27: 45/45 backend tests passed (14 auth, 11 lifecycle, 4 compatibility, 16 progression), TypeScript and bundle build clean. New checks cover fresh/legacy/concurrent migration, checksum and environment rollback, immutable catalog/journal, concurrent idempotent grants, payload conflicts, ownership across versions, loadout ownership/version constraints, malformed JSON metadata and absent public reward routes. PostgreSQL 18.4 reported x86_64 Darwin; this is not an ARM capacity result. Browser tests were explicitly deferred for this stage.

References: [Fastify testing](https://fastify.dev/docs/latest/Guides/Testing/), [static plugin compatibility](https://github.com/fastify/fastify-static), [embedded PostgreSQL runtime](https://github.com/leinelissen/embedded-postgres).
