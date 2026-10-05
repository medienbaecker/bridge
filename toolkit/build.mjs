// node build.mjs vendor           builds dist/vendor.js, dist/mantine.css and the shims (once, at install)
// node build.mjs page X.jsx OUT   builds OUT/page.js and OUT/index.html for one page; on failure prints JSON errors and exits 1
import * as esbuild from 'esbuild';
import { readFileSync, writeFileSync, mkdirSync, existsSync, copyFileSync, statSync } from 'node:fs';
import { dirname, resolve, basename } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const dist = resolve(here, 'dist');
const modules = ['react', 'react-dom', 'react-dom/client', 'react/jsx-runtime', '@mantine/core', '@mantine/hooks'];
const key = (name) => name.replace(/[@/]/g, '_');

async function vendor() {
  mkdirSync(resolve(dist, 'shims'), { recursive: true });
  const entry = modules.map((m, i) => `import * as m${i} from '${m}';`).join('\n')
    + `\nglobalThis.__bridgeVendor = { ${modules.map((m, i) => `'${m}': m${i}`).join(', ')} };\n`;
  writeFileSync(resolve(dist, 'vendor-entry.js'), entry);
  await esbuild.build({
    entryPoints: [resolve(dist, 'vendor-entry.js')],
    bundle: true, minify: true, format: 'iife', platform: 'browser', target: 'safari26',
    define: { 'process.env.NODE_ENV': '"production"' },
    outfile: resolve(dist, 'vendor.js'),
    logLevel: 'error',
  });
  for (const m of modules) {
    const names = Object.keys(await import(m)).filter((n) => n !== 'default');
    const lines = [`const v = globalThis.__bridgeVendor['${m}'];`, 'export default v.default ?? v;']
      .concat(names.map((n) => `export const ${n} = v.${n};`));
    writeFileSync(resolve(dist, 'shims', key(m) + '.js'), lines.join('\n') + '\n');
  }
  copyFileSync(resolve(here, 'node_modules/@mantine/core/styles.css'), resolve(dist, 'mantine.css'));
  console.log('vendor built');
}

async function page(source, out) {
  mkdirSync(out, { recursive: true });
  const shims = {
    name: 'bridge-shims',
    setup(build) {
      build.onResolve({ filter: /^@bridge$/ }, () => ({ path: resolve(here, 'bridge.js') }));
      build.onResolve({ filter: /^@page$/ }, () => ({ path: resolve(source) }));
      build.onResolve({ filter: /.*/ }, (args) => modules.includes(args.path) ? { path: resolve(dist, 'shims', key(args.path) + '.js') } : undefined);
    },
  };
  try {
    await esbuild.build({
      entryPoints: [resolve(here, 'scaffold.jsx')],
      bundle: true, format: 'iife', platform: 'browser', target: 'safari26', jsx: 'automatic',
      define: { 'process.env.NODE_ENV': '"production"' },
      plugins: [shims],
      outfile: resolve(out, 'page.js'),
      logLevel: 'silent',
      absWorkingDir: dirname(resolve(source)),
    });
  } catch (e) {
    const errors = (e.errors || [{ text: String(e) }]).map((err) => ({
      text: err.text,
      file: err.location?.file, line: err.location?.line, column: err.location?.column, lineText: err.location?.lineText,
    }));
    process.stdout.write(JSON.stringify({ errors }));
    process.exit(1);
  }
  const dataFile = resolve(source).replace(/\.[jt]sx$/, '.data.json');
  let data = 'null';
  if (existsSync(dataFile)) {
    try { data = JSON.stringify(JSON.parse(readFileSync(dataFile, 'utf8'))); }
    catch (e) { process.stdout.write(JSON.stringify({ errors: [{ text: 'page.data.json is not valid JSON: ' + e.message, file: dataFile }] })); process.exit(1); }
  }
  const stamp = (file) => `?v=${Math.floor(statSync(file).mtimeMs)}`;
  const parsed = data === 'null' ? null : JSON.parse(data);
  const title = (parsed && typeof parsed.title === 'string' ? parsed.title : basename(source).replace(/\.[jt]sx$/, '')).replace(/</g, '&lt;');
  writeFileSync(resolve(out, 'index.html'), `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>${title}</title>
<link rel="stylesheet" href="${pathToFileURL(resolve(dist, 'mantine.css')).href}${stamp(resolve(dist, 'mantine.css'))}">
<link rel="stylesheet" href="${pathToFileURL(resolve(here, 'theme.css')).href}${stamp(resolve(here, 'theme.css'))}">
<script>window.__bridgeData = ${data.replace(/</g, '\\u003c')};</script>
</head>
<body>
<div id="root"></div>
<script src="${pathToFileURL(resolve(dist, 'vendor.js')).href}${stamp(resolve(dist, 'vendor.js'))}"></script>
<script src="page.js?v=${Date.now()}"></script>
</body>
</html>
`);
  process.stdout.write(JSON.stringify({ ok: true, out }));
}

const [mode, a, b] = process.argv.slice(2);
if (mode === 'vendor') await vendor();
else if (mode === 'page' && a && b) await page(a, b);
else { console.error('usage: build.mjs vendor | build.mjs page <file.jsx> <outdir>'); process.exit(2); }
