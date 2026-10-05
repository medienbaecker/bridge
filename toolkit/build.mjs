// node build.mjs vendor   builds dist/vendor.js, dist/mantine.css and the shims, and copies esbuild to bin/ (at install or release)
import * as esbuild from 'esbuild';
import { writeFileSync, mkdirSync, copyFileSync, rmSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

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
  mkdirSync(resolve(here, 'bin'), { recursive: true });
  // A binary rewritten in place keeps its old cached signature, and macOS kills it on the next run.
  rmSync(resolve(here, 'bin/esbuild'), { force: true });
  copyFileSync(resolve(here, 'node_modules/@esbuild/darwin-arm64/bin/esbuild'), resolve(here, 'bin/esbuild'));
  console.log('vendor built');
}

if (process.argv[2] === 'vendor') await vendor();
else { console.error('usage: build.mjs vendor'); process.exit(2); }
