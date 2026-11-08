// Builds everything the desktop app runs:
//   dist/                  renderer (Vite production build)
//   desktop-dist/main.mjs  Electron main process + the Express backend, bundled (no node_modules needed)
//   desktop-dist/preload.cjs  sandboxed preload (contextBridge only)
//   desktop-dist/startup.html startup-error page, with a CSP hash for its inline script
// Usage: npm run desktop:build
import { build } from 'esbuild';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const out = join(root, 'desktop-dist');
rmSync(out, { recursive: true, force: true });
mkdirSync(out, { recursive: true });

console.log('• renderer (vite build)');
execFileSync(process.execPath, [join(root, 'node_modules', 'vite', 'bin', 'vite.js'), 'build', '--logLevel', 'warn'], { cwd: root, stdio: 'inherit' });

console.log('• main process + backend (esbuild)');
const pkg = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8'));
await build({
  entryPoints: [join(root, 'desktop', 'main.ts')],
  outfile: join(out, 'main.mjs'),
  bundle: true,
  platform: 'node',
  format: 'esm',
  target: 'node22',
  external: ['electron'],
  // Bundled CommonJS dependencies (express, multer) call require() for Node built-ins.
  banner: { js: "import { createRequire as __studioCreateRequire } from 'node:module'; const require = __studioCreateRequire(import.meta.url);" },
  define: { 'process.env.PRESENTATION_STUDIO_VERSION': JSON.stringify(pkg.version) },
  legalComments: 'none',
  sourcemap: false,
  logLevel: 'warning',
});

console.log('• preload (esbuild)');
await build({
  entryPoints: [join(root, 'desktop', 'preload.ts')],
  outfile: join(out, 'preload.cjs'),
  bundle: true,
  platform: 'node',
  format: 'cjs',
  target: 'node22',
  external: ['electron'],
  logLevel: 'warning',
});

console.log('• startup page');
let html = readFileSync(join(root, 'desktop', 'startup.html'), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const hash = createHash('sha256').update(script).digest('base64');
html = html.replace('sha256-REPLACED_AT_BUILD', `sha256-${hash}`);
writeFileSync(join(out, 'startup.html'), html);

console.log(`Desktop build ready in ${out}`);
