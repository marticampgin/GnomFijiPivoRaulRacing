import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { access, mkdir, readFile, rename, rm, stat } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const lock = JSON.parse(await readFile(resolve(root, 'tooling/godot.json'), 'utf8'));
const destination = resolve(root, lock.templateDirectory);

async function digest(path) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(path)) hash.update(chunk);
  return hash.digest('hex');
}

async function verifyTemplates() {
  for (const [name, expected] of Object.entries(lock.templates)) {
    const actual = await digest(resolve(destination, name));
    if (actual !== expected) throw new Error(`Template checksum mismatch: ${name}`);
  }
}

async function install() {
  const args = process.argv.slice(2);
  const checkOnly = args.length === 1 && args[0] === '--check';
  const archiveIndex = args.indexOf('--archive');
  const suppliedArchive = archiveIndex === 0 && args.length === 2 ? resolve(args[1]) : null;
  if (args.length && !checkOnly && !suppliedArchive) {
    throw new Error('Usage: node scripts/setup-godot.mjs [--check | --archive <official.tpz>]');
  }
  if (checkOnly) {
    await verifyTemplates();
    console.log(`Godot ${lock.version} templates verified.`);
    return;
  }
  try {
    await verifyTemplates();
    console.log(`Godot ${lock.version} templates already installed and verified.`);
    return;
  } catch {
    // Repair missing or altered local templates only from the pinned archive.
  }
  await mkdir(destination, { recursive: true });
  const archive = suppliedArchive ?? resolve(destination, 'export_templates.tpz');
  let exists = true;
  try { await access(archive); } catch { exists = false; }
  if (!exists && suppliedArchive) throw new Error(`Archive not found: ${archive}`);
  if (!exists) {
    console.log(`Downloading official Godot ${lock.version} templates (${lock.archive.bytes} bytes).`);
    const response = await fetch(lock.archive.url);
    if (!response.ok || !response.body) throw new Error(`Template download failed: HTTP ${response.status}`);
    const partial = `${archive}.partial`;
    try {
      await pipeline(Readable.fromWeb(response.body), createWriteStream(partial));
      if ((await stat(partial)).size !== lock.archive.bytes || await digest(partial) !== lock.archive.sha256) {
        throw new Error('Downloaded template archive does not match the pinned checksum.');
      }
      await rename(partial, archive);
    } catch (error) {
      await rm(partial, { force: true });
      throw error;
    }
  }
  if ((await stat(archive)).size !== lock.archive.bytes || await digest(archive) !== lock.archive.sha256) {
    throw new Error('Template archive checksum mismatch; no files were extracted.');
  }
  const entries = Object.keys(lock.templates).map((name) => `templates/${name}`);
  const extraction = spawnSync('unzip', ['-j', '-o', archive, ...entries, '-d', destination], { stdio: 'inherit' });
  if (extraction.error) throw extraction.error;
  if (extraction.status !== 0) throw new Error('Template extraction failed. Install unzip and retry.');
  await verifyTemplates();
  console.log(`Godot ${lock.version} templates installed and verified in ${destination}.`);
}

try {
  await install();
} catch (error) {
  console.error(error.message);
  process.exitCode = 1;
}
