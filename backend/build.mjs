import { build } from 'esbuild';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('./', import.meta.url));
console.log('GNOM backend: building runtime and integration tests');
await build({
  absWorkingDir: root,
  entryPoints: { local: 'src/local.ts', server: 'src/server.ts', 'auth.test': 'test/auth.test.ts', 'local-lifecycle.test': 'test/local-lifecycle.test.ts' },
  outdir: 'dist', outExtension: { '.js': '.mjs' },
  bundle: true, platform: 'node', target: 'node24', format: 'esm',
  external: ['embedded-postgres', 'pg-native'],
  banner: { js: "import { createRequire as __createRequire } from 'node:module'; import { fileURLToPath as __fileURLToPath } from 'node:url'; import { dirname as __dirnameOf } from 'node:path'; const require = __createRequire(import.meta.url); const __filename = __fileURLToPath(import.meta.url); const __dirname = __dirnameOf(__filename);" },
  logLevel: 'info',
});
