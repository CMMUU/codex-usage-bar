import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { resolve, dirname } from 'node:path';
import { locales, ORIGIN } from '../src/content.mjs';
import { renderPage, previewContent } from '../src/render-page.mjs';

const root = fileURLToPath(new URL('../public/', import.meta.url));
const outputs = new Map();
const hashes = [];
for (const [locale, t] of Object.entries(locales)) {
  const { html, jsonHash } = renderPage(locale);
  hashes.push(`'sha256-${jsonHash}'`);
  outputs.set(`${t.path}index.html`, html);
  outputs.set(`${t.path}manifest.webmanifest`, JSON.stringify({ name: 'Codex Usage Bar', short_name: 'Codex Usage', description: t.description, lang: t.lang, start_url: t.path, scope: '/', display: 'standalone', background_color: '#FAFBFE', theme_color: '#FAFBFE', icons: [192, 512].map(size => ({ src: `/assets/icon-${size}.png?v=quota-orbit-20261003`, sizes: `${size}x${size}`, type: 'image/png' })) }, null, 2) + '\n');
}
outputs.set('/preview-content.js', 'export const data = ' + previewContent() + ';\n');
outputs.set('/_headers', `/*
  Content-Security-Policy: default-src 'self'; connect-src 'self'; img-src 'self' data:; font-src 'self'; script-src 'self' ${hashes.join(' ')}; style-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'
  Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=()
  Referrer-Policy: strict-origin-when-cross-origin
  X-Content-Type-Options: nosniff
  X-Frame-Options: DENY

/assets/*
  Cache-Control: public, max-age=31536000, immutable

/*.webmanifest
  Cache-Control: public, max-age=86400

/sitemap.xml
  Cache-Control: public, max-age=3600
`);
outputs.set('/sitemap.xml', `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9" xmlns:xhtml="http://www.w3.org/1999/xhtml">
${Object.values(locales).map(t => `  <url><loc>${ORIGIN}${t.path}</loc><xhtml:link rel="alternate" hreflang="zh-Hans" href="${ORIGIN}/"/><xhtml:link rel="alternate" hreflang="en" href="${ORIGIN}/en/"/><xhtml:link rel="alternate" hreflang="x-default" href="${ORIGIN}/"/></url>`).join('\n')}
</urlset>
`);
outputs.set('/robots.txt', `User-agent: *\nAllow: /\nDisallow: /api/\nSitemap: ${ORIGIN}/sitemap.xml\n`);
outputs.set('/404.html', `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="robots" content="noindex"><title>Page not found — Codex Usage Bar</title><link rel="stylesheet" href="/styles.css?v=20261003b"></head><body><main class="not-found wrap"><img src="/assets/brand-mark.png?v=quota-orbit-20261003" width="64" height="64" alt="Codex Usage Bar"><h1>A little off track.</h1><p>This page has moved, or does not exist.</p><p lang="zh-Hans">这个页面已移动，或暂时不存在。</p><div class="hero-actions"><a class="button" href="/en/">Back to the website</a><a class="source-link" href="/" lang="zh-Hans">返回中文官网 →</a></div></main></body></html>\n`);

const check = process.argv.includes('--check');
for (const [path, content] of outputs) {
  const target = resolve(root, '.' + path);
  if (check) {
    if (await readFile(target, 'utf8').catch(() => '') !== content) throw new Error(`Stale generated file: ${path}. Run npm run build.`);
  } else {
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, content);
  }
}
console.log(`${check ? 'Verified' : 'Built'} ${outputs.size} bilingual website files.`);
