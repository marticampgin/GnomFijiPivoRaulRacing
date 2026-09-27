import { createHash } from 'node:crypto';
import type { Pool } from 'pg';
import { transaction } from './database.js';

export type ProgressionErrorCode = 'invalid_catalog' | 'catalog_conflict' | 'item_kind_conflict'
  | 'invalid_grant' | 'account_not_found' | 'catalog_not_found' | 'item_not_in_catalog' | 'operation_conflict';

export class ProgressionError extends Error {
  constructor(readonly code: ProgressionErrorCode) { super(code); }
}

type ItemKind = 'vehicle' | 'character' | 'part' | 'cosmetic';
type JsonValue = null | boolean | number | string | JsonValue[] | { [key: string]: JsonValue };
interface CatalogItem { id: string; kind: ItemKind; definition: { [key: string]: JsonValue } }
interface CatalogInput { version: string; items: CatalogItem[] }
interface GrantInput { operationId: string; accountId: string; catalogVersion: string; source: string; items: string[] }
export interface GrantResult {
  operationId: string;
  accountId: string;
  catalogVersion: string;
  source: string;
  grants: { itemId: string; alreadyOwned: boolean }[];
}

const identifier = (value: unknown): value is string => typeof value === 'string' && /^[a-z0-9][a-z0-9._-]{0,63}$/.test(value);
const uuid = (value: unknown): value is string => typeof value === 'string' && /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i.test(value);
const record = (value: unknown): value is Record<string, unknown> => value !== null && typeof value === 'object'
  && [Object.prototype, null].includes(Object.getPrototypeOf(value));
const exactKeys = (value: Record<string, unknown>, keys: string[]) => Reflect.ownKeys(value).length === keys.length
  && keys.every(key => Object.hasOwn(value, key));
const digest = (value: string) => createHash('sha256').update(value).digest('hex');
const compare = (left: string, right: string) => left < right ? -1 : left > right ? 1 : 0;
const invalid = (code: ProgressionErrorCode): never => { throw new ProgressionError(code); };
const jsonString = (value: string) => !value.includes('\0') && !/[\uD800-\uDFFF]/u.test(value);

function canonicalDefinition(value: unknown): { [key: string]: JsonValue } {
  if (!record(value)) return invalid('invalid_catalog');
  let nodes = 0;
  const visit = (current: unknown, depth: number): JsonValue => {
    if (++nodes > 4096 || depth > 12) return invalid('invalid_catalog');
    if (current === null || typeof current === 'boolean') return current;
    if (typeof current === 'string') return jsonString(current) ? current : invalid('invalid_catalog');
    if (typeof current === 'number' && Number.isFinite(current)) return current === 0 ? 0 : current;
    if (Array.isArray(current)) {
      if (current.length > 4096) return invalid('invalid_catalog');
      return Array.from(current, item => visit(item, depth + 1));
    }
    if (!record(current) || Reflect.ownKeys(current).some(key => typeof key !== 'string')) return invalid('invalid_catalog');
    const result: { [key: string]: JsonValue } = Object.create(null);
    for (const key of Object.keys(current).sort(compare)) {
      if (!jsonString(key)) return invalid('invalid_catalog');
      result[key] = visit(current[key], depth + 1);
    }
    return result;
  };
  const result = visit(value, 0) as { [key: string]: JsonValue };
  // jsonb includes spaces when rendered; leave room below the database's 16 KiB bound.
  if (Buffer.byteLength(JSON.stringify(result)) > 12000) return invalid('invalid_catalog');
  return result;
}

function catalogInput(input: unknown): CatalogInput {
  if (!record(input) || !exactKeys(input, ['version', 'items']) || !identifier(input.version)
    || !Array.isArray(input.items) || !input.items.length || input.items.length > 256) return invalid('invalid_catalog');
  const items: CatalogItem[] = Array.from(input.items, item => {
    if (!record(item) || !exactKeys(item, ['id', 'kind', 'definition']) || !identifier(item.id)
      || !['vehicle', 'character', 'part', 'cosmetic'].includes(item.kind as string)) return invalid('invalid_catalog');
    return { id: item.id, kind: item.kind as ItemKind, definition: canonicalDefinition(item.definition) };
  }).sort((left, right) => compare(left.id, right.id));
  if (new Set(items.map(item => item.id)).size !== items.length) return invalid('invalid_catalog');
  const result = { version: input.version, items };
  if (Buffer.byteLength(JSON.stringify(result)) > 1024 * 1024) return invalid('invalid_catalog');
  return result;
}

function grantInput(input: unknown): GrantInput {
  if (!record(input) || !exactKeys(input, ['operationId', 'accountId', 'catalogVersion', 'source', 'items'])
    || !uuid(input.operationId) || !uuid(input.accountId) || !identifier(input.catalogVersion) || !identifier(input.source)
    || !Array.isArray(input.items) || !input.items.length || input.items.length > 64 || !Array.from(input.items).every(identifier)
    || new Set(input.items).size !== input.items.length) return invalid('invalid_grant');
  return {
    operationId: input.operationId.toLowerCase(), accountId: input.accountId.toLowerCase(),
    catalogVersion: input.catalogVersion, source: input.source, items: [...input.items].sort(compare),
  };
}

// Internal trusted operations only: browser race results are not evidence of entitlement.
export class ProgressionService {
  constructor(readonly pool: Pool) {}

  async publishCatalog(input: unknown): Promise<{ version: string; itemCount: number }> {
    const catalog = catalogInput(input), contentHash = digest(JSON.stringify(catalog));
    return transaction(this.pool, async client => {
      await client.query('SELECT pg_advisory_xact_lock(74189231)');
      const existing = (await client.query('SELECT content_hash,published FROM catalog_version WHERE version=$1', [catalog.version])).rows[0];
      if (existing) {
        if (existing.content_hash !== contentHash || !existing.published) return invalid('catalog_conflict');
        return { version: catalog.version, itemCount: catalog.items.length };
      }
      await client.query('INSERT INTO catalog_version(version,content_hash) VALUES($1,$2)', [catalog.version, contentHash]);
      for (const item of catalog.items) {
        await client.query('INSERT INTO catalog_item(id,kind) VALUES($1,$2) ON CONFLICT DO NOTHING', [item.id, item.kind]);
        const stored = (await client.query('SELECT kind FROM catalog_item WHERE id=$1', [item.id])).rows[0];
        if (stored.kind !== item.kind) return invalid('item_kind_conflict');
        try {
          await client.query('INSERT INTO catalog_definition(catalog_version,item_id,definition) VALUES($1,$2,$3::jsonb)', [catalog.version, item.id, JSON.stringify(item.definition)]);
        } catch (error) {
          if ((error as { code?: string; constraint?: string }).code === '23514'
            && (error as { constraint?: string }).constraint === 'catalog_definition_definition_check') return invalid('invalid_catalog');
          throw error;
        }
      }
      await client.query('UPDATE catalog_version SET published=true WHERE version=$1', [catalog.version]);
      return { version: catalog.version, itemCount: catalog.items.length };
    });
  }

  async grantEntitlements(input: unknown): Promise<GrantResult> {
    const grant = grantInput(input), requestHash = digest(JSON.stringify(grant));
    return transaction(this.pool, async client => {
      const lock = createHash('sha256').update(grant.operationId).digest();
      await client.query('SELECT pg_advisory_xact_lock($1,$2)', [lock.readInt32BE(0), lock.readInt32BE(4)]);
      const existing = (await client.query('SELECT request_hash,result,completed FROM reward_operation WHERE operation_id=$1', [grant.operationId])).rows[0];
      if (existing) {
        if (existing.request_hash !== requestHash || !existing.completed) return invalid('operation_conflict');
        return existing.result as GrantResult;
      }
      // Serialize distinct grants for one owner before observing already-owned state.
      const account = await client.query('SELECT id FROM account WHERE id=$1 FOR UPDATE', [grant.accountId]);
      if (!account.rowCount) return invalid('account_not_found');
      const catalog = await client.query('SELECT version FROM catalog_version WHERE version=$1 AND published', [grant.catalogVersion]);
      if (!catalog.rowCount) return invalid('catalog_not_found');
      const definitions = await client.query('SELECT item_id FROM catalog_definition WHERE catalog_version=$1 AND item_id=ANY($2::text[])', [grant.catalogVersion, grant.items]);
      if (definitions.rowCount !== grant.items.length) return invalid('item_not_in_catalog');
      const inventory = await client.query('SELECT item_id FROM inventory_entry WHERE account_id=$1 AND item_id=ANY($2::text[])', [grant.accountId, grant.items]);
      const owned = new Set<string>(inventory.rows.map(row => row.item_id));
      const result: GrantResult = {
        operationId: grant.operationId, accountId: grant.accountId, catalogVersion: grant.catalogVersion, source: grant.source,
        grants: grant.items.map(itemId => ({ itemId, alreadyOwned: owned.has(itemId) })),
      };
      await client.query(`INSERT INTO reward_operation(operation_id,account_id,catalog_version,source,request_hash,result)
        VALUES($1,$2,$3,$4,$5,$6::jsonb)`, [grant.operationId, grant.accountId, grant.catalogVersion, grant.source, requestHash, JSON.stringify(result)]);
      for (const item of result.grants) {
        await client.query(`INSERT INTO reward_grant(operation_id,item_id,account_id,catalog_version,already_owned)
          VALUES($1,$2,$3,$4,$5)`, [grant.operationId, item.itemId, grant.accountId, grant.catalogVersion, item.alreadyOwned]);
        if (!item.alreadyOwned) await client.query(`INSERT INTO inventory_entry(account_id,item_id,grant_operation_id,catalog_version)
          VALUES($1,$2,$3,$4)`, [grant.accountId, item.itemId, grant.operationId, grant.catalogVersion]);
      }
      await client.query('UPDATE reward_operation SET completed=true WHERE operation_id=$1', [grant.operationId]);
      return result;
    });
  }
}
