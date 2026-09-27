CREATE TABLE catalog_version (
  version text PRIMARY KEY CHECK (version ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  content_hash char(64) NOT NULL CHECK (content_hash ~ '^[a-f0-9]{64}$'),
  published boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (version, published)
);

CREATE TABLE catalog_item (
  id text PRIMARY KEY CHECK (id ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  kind text NOT NULL CHECK (kind IN ('vehicle', 'character', 'part', 'cosmetic'))
);

CREATE TABLE catalog_definition (
  catalog_version text NOT NULL REFERENCES catalog_version(version),
  item_id text NOT NULL REFERENCES catalog_item(id),
  definition jsonb NOT NULL CHECK (jsonb_typeof(definition) = 'object' AND octet_length(definition::text) <= 16384),
  PRIMARY KEY (catalog_version, item_id)
);
CREATE INDEX catalog_definition_item ON catalog_definition(item_id);

CREATE FUNCTION progression_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION '% is immutable', TG_TABLE_NAME USING ERRCODE = '23514';
END;
$$;

CREATE FUNCTION progression_publish_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.published OR NOT NEW.published OR
     ROW(NEW.version, NEW.content_hash, NEW.created_at) IS DISTINCT FROM
     ROW(OLD.version, OLD.content_hash, OLD.created_at) THEN
    RAISE EXCEPTION 'Catalog versions can only be published once' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION progression_definition_insert() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE is_published boolean;
BEGIN
  SELECT published INTO is_published FROM catalog_version WHERE version = NEW.catalog_version FOR SHARE;
  IF is_published THEN
    RAISE EXCEPTION 'Published catalog definitions are immutable' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER catalog_version_publish BEFORE UPDATE ON catalog_version
  FOR EACH ROW EXECUTE FUNCTION progression_publish_only();
CREATE TRIGGER catalog_version_delete BEFORE DELETE ON catalog_version
  FOR EACH ROW EXECUTE FUNCTION progression_immutable();
CREATE TRIGGER catalog_item_immutable BEFORE UPDATE OR DELETE ON catalog_item
  FOR EACH ROW EXECUTE FUNCTION progression_immutable();
CREATE TRIGGER catalog_definition_insert BEFORE INSERT ON catalog_definition
  FOR EACH ROW EXECUTE FUNCTION progression_definition_insert();
CREATE TRIGGER catalog_definition_immutable BEFORE UPDATE OR DELETE ON catalog_definition
  FOR EACH ROW EXECUTE FUNCTION progression_immutable();

CREATE TABLE reward_operation (
  operation_id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES account(id),
  catalog_version text NOT NULL,
  catalog_published boolean NOT NULL DEFAULT true CHECK (catalog_published),
  source text NOT NULL CHECK (source ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  request_hash char(64) NOT NULL CHECK (request_hash ~ '^[a-f0-9]{64}$'),
  result jsonb NOT NULL CHECK (jsonb_typeof(result) = 'object'),
  completed boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (operation_id, account_id, catalog_version),
  FOREIGN KEY (catalog_version, catalog_published) REFERENCES catalog_version(version, published)
);
CREATE INDEX reward_operation_account ON reward_operation(account_id, created_at);
CREATE INDEX reward_operation_catalog ON reward_operation(catalog_version, catalog_published);

CREATE TABLE reward_grant (
  operation_id uuid NOT NULL,
  item_id text NOT NULL,
  account_id uuid NOT NULL,
  catalog_version text NOT NULL,
  already_owned boolean NOT NULL,
  PRIMARY KEY (operation_id, item_id),
  UNIQUE (operation_id, item_id, account_id, catalog_version),
  FOREIGN KEY (operation_id, account_id, catalog_version)
    REFERENCES reward_operation(operation_id, account_id, catalog_version),
  FOREIGN KEY (catalog_version, item_id) REFERENCES catalog_definition(catalog_version, item_id)
);
CREATE INDEX reward_grant_definition ON reward_grant(catalog_version, item_id);

CREATE TABLE inventory_entry (
  account_id uuid NOT NULL REFERENCES account(id),
  item_id text NOT NULL REFERENCES catalog_item(id),
  grant_operation_id uuid NOT NULL,
  catalog_version text NOT NULL,
  acquired_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (account_id, item_id),
  FOREIGN KEY (grant_operation_id, item_id, account_id, catalog_version)
    REFERENCES reward_grant(operation_id, item_id, account_id, catalog_version)
);
CREATE INDEX inventory_entry_item ON inventory_entry(item_id);
CREATE INDEX inventory_entry_grant ON inventory_entry(grant_operation_id, item_id, account_id, catalog_version);

CREATE FUNCTION progression_complete_only() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF OLD.completed OR NOT NEW.completed OR
     (to_jsonb(NEW) - 'completed') IS DISTINCT FROM (to_jsonb(OLD) - 'completed') THEN
    RAISE EXCEPTION 'Reward operations can only be completed once' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE FUNCTION progression_grant_insert() RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE is_completed boolean;
BEGIN
  SELECT completed INTO is_completed FROM reward_operation WHERE operation_id = NEW.operation_id FOR SHARE;
  IF is_completed THEN
    RAISE EXCEPTION 'Completed reward grants are immutable' USING ERRCODE = '23514';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER reward_operation_complete BEFORE UPDATE ON reward_operation
  FOR EACH ROW EXECUTE FUNCTION progression_complete_only();
CREATE TRIGGER reward_operation_delete BEFORE DELETE ON reward_operation
  FOR EACH ROW EXECUTE FUNCTION progression_immutable();
CREATE TRIGGER reward_grant_insert BEFORE INSERT ON reward_grant
  FOR EACH ROW EXECUTE FUNCTION progression_grant_insert();
CREATE TRIGGER reward_grant_immutable BEFORE UPDATE OR DELETE ON reward_grant
  FOR EACH ROW EXECUTE FUNCTION progression_immutable();

CREATE TABLE loadout (
  id uuid PRIMARY KEY,
  account_id uuid NOT NULL REFERENCES account(id),
  catalog_version text NOT NULL,
  catalog_published boolean NOT NULL DEFAULT true CHECK (catalog_published),
  style_id text NOT NULL CHECK (style_id IN ('handling', 'acceleration', 'speed', 'drift')),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id, account_id, catalog_version),
  FOREIGN KEY (catalog_version, catalog_published) REFERENCES catalog_version(version, published)
);
CREATE INDEX loadout_account ON loadout(account_id);
CREATE INDEX loadout_catalog ON loadout(catalog_version, catalog_published);

CREATE TABLE loadout_item (
  loadout_id uuid NOT NULL,
  account_id uuid NOT NULL,
  catalog_version text NOT NULL,
  slot_id text NOT NULL CHECK (slot_id ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  item_id text NOT NULL,
  PRIMARY KEY (loadout_id, slot_id),
  FOREIGN KEY (loadout_id, account_id, catalog_version)
    REFERENCES loadout(id, account_id, catalog_version) ON DELETE CASCADE,
  FOREIGN KEY (account_id, item_id) REFERENCES inventory_entry(account_id, item_id),
  FOREIGN KEY (catalog_version, item_id) REFERENCES catalog_definition(catalog_version, item_id)
);
CREATE INDEX loadout_item_inventory ON loadout_item(account_id, item_id);
CREATE INDEX loadout_item_definition ON loadout_item(catalog_version, item_id);
