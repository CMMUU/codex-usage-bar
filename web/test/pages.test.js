import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, access } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { renderPage } from '../src/render-page.mjs';
import { locales, DOWNLOAD, ORIGIN } from '../src/content.mjs';

for (const [locale, t] of Object.entries(locales)) {
  test(`${locale} is a complete localized document without client-side translation`, () => {
    const { html } = renderPage(locale);
    assert.ok(html.includes(`<html lang="${t.lang}"`));
    assert.ok(html.includes(`<title>${t.title}</title>`));
    assert.ok(html.includes(`rel="canonical" href="${ORIGIN}${t.path}"`));
    assert.ok(html.includes(`href="${t.otherPath}" lang="${t.otherLang}"`));
    for (const heading of t.heading) assert.ok(html.includes(heading));
    for (const [question, answer] of t.faqs) {
      assert.ok(html.includes(question));
      assert.ok(html.includes(answer));
    }
    assert.equal((html.match(new RegExp(`href="${DOWNLOAD}"`, 'g')) ?? []).length, 2);
    assert.ok(!html.includes('data-i18n'));
    assert.equal((html.match(/<h1 /g) ?? []).length, 1);
    for (const target of html.matchAll(/href="#([^"]+)"/g)) assert.ok(html.includes(`id="${target[1]}"`));
  });
  test(`${locale} metadata is accepted by the deployed CSP`, async () => {
    const { html, jsonHash } = renderPage(locale);
    const script = html.match(/<script type="application\/ld\+json">([^<]+)<\/script>/)[1];
    const schema = JSON.parse(script);
    assert.equal(schema.url, ORIGIN + t.path);
    assert.equal(schema.inLanguage, t.lang);
    assert.equal(schema.downloadUrl, DOWNLOAD);
    assert.equal(createHash('sha256').update(script).digest('base64'), jsonHash);
    const headers = await readFile(new URL('../public/_headers', import.meta.url), 'utf8');
    assert.ok(headers.includes(`'sha256-${jsonHash}'`));
    assert.ok(!headers.includes('unsafe-inline'));
  });
}

test('locale routes and the sitemap share canonical alternates', async () => {
  const sitemap = await readFile(new URL('../public/sitemap.xml', import.meta.url), 'utf8');
  for (const t of Object.values(locales)) assert.ok(sitemap.includes(`<loc>${ORIGIN}${t.path}</loc>`));
  assert.equal((sitemap.match(/hreflang="en"/g) ?? []).length, 2);
  assert.equal((sitemap.match(/hreflang="zh-Hans"/g) ?? []).length, 2);
});

test('font payloads match their declared WOFF2 format', async () => {
  for (const family of ['instrument-serif', 'instrument-serif-italic', 'manrope', 'noto-serif-sc']) {
    const bytes = await readFile(new URL(`../public/assets/fonts/${family}.woff2`, import.meta.url));
    assert.equal(bytes.subarray(0, 4).toString(), 'wOF2', family);
  }
});

test('all same-origin page links, icons, and script assets exist in the deploy bundle', async () => {
  const publicRoot = new URL('../public/', import.meta.url);
  for (const locale of Object.keys(locales)) {
    const { html } = renderPage(locale);
    const paths = new Set([...html.matchAll(/(?:href|src)="(\/[^"?]*)(?:\?[^" ]*)?"/g)].map(m => m[1]));
    for (const path of paths) {
      const file = path.endsWith('/') ? path + 'index.html' : path;
      await assert.doesNotReject(access(new URL('.' + file, publicRoot)), `${locale}: ${path}`);
    }
  }
});
