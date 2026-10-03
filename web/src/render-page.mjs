import { createHash } from 'node:crypto';
import { locales, previews, DOWNLOAD, SOURCE, CENTER, ORIGIN } from './content.mjs';

const escape = (value) => String(value).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const icon = (name, cls = '') => {
  const paths = {
    download: '<path d="M12 3v12m-5-5 5 5 5-5M4 15v5h16v-5"/>',
    arrow: '<path d="M4 12h16m-6-6 6 6-6 6"/>',
    moon: '<path d="M20.5 14A9 9 0 0 1 10 3.5 9 9 0 1 0 20.5 14Z"/>',
    sun: '<circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M2 12h2m16 0h2M5 5l1.4 1.4m11.2 11.2L19 19M5 19l1.4-1.4M17.6 6.4 19 5"/>',
    clock: '<circle cx="12" cy="12" r="9"/><path d="M12 6v6l4 3"/>',
    wifi: '<path d="M2 8a16 16 0 0 1 20 0M5 12a11 11 0 0 1 14 0M8 16a6 6 0 0 1 8 0M12 20h.01"/>',
    search: '<circle cx="10" cy="10" r="7"/><path d="m15 15 6 6"/>',
    sliders: '<rect x="3" y="3" width="18" height="7" rx="3.5"/><rect x="3" y="14" width="18" height="7" rx="3.5"/><path d="M8 6.5h.01M16 17.5h.01"/>',
  };
  return `<svg class="icon ${cls}" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths[name]}</svg>`;
};
const mark = (cls = '') => `<img class="brand-mark ${cls}" src="/assets/brand-mark.png?v=quota-orbit-20261003" width="48" height="48" alt="">`;
const download = (t, cls = '') => `<a class="button download-link ${cls}" href="${DOWNLOAD}">${cls ? `<span>${t.download}</span>${icon('arrow')}` : `${icon('download')}<span>${t.download}</span>`}</a>`;
const lines = (items) => items.map((s) => `<span>${escape(s)}</span>`).join('');
const ring = (id) => `<div class="ring"><svg viewBox="0 0 160 160" aria-hidden="true"><defs><linearGradient id="${id}" x1="0" y1="0" x2="1" y2="1"><stop offset="0%" stop-color="#473aee"/><stop offset="100%" stop-color="#6d97ff"/></linearGradient></defs><circle class="ring-track" cx="80" cy="80" r="67"/><circle class="ring-progress" cx="80" cy="80" r="67" pathLength="100" stroke="url(#${id})" stroke-dasharray="64 100"/></svg><strong data-demo="used">64%</strong></div>`;

export function renderPage(locale) {
  const t = locales[locale];
  const structured = JSON.stringify({ '@context': 'https://schema.org', '@type': 'SoftwareApplication', name: 'Codex Usage Bar', operatingSystem: 'macOS 13+', applicationCategory: 'UtilitiesApplication', url: ORIGIN + t.path, description: t.description, inLanguage: t.lang, downloadUrl: DOWNLOAD, offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' }, author: { '@type': 'Person', name: 'CMMUU', url: 'https://github.com/CMMUU' } });
  const jsonHash = createHash('sha256').update(structured).digest('base64');
  const html = `<!doctype html>
<html lang="${t.lang}" data-provider="codex" data-widget-size="small">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>${escape(t.title)}</title>
  <meta name="description" content="${escape(t.description)}">
  <meta name="theme-color" content="#FAFBFE">
  <link rel="canonical" href="${ORIGIN}${t.path}">
  <link rel="alternate" hreflang="zh-Hans" href="${ORIGIN}/">
  <link rel="alternate" hreflang="en" href="${ORIGIN}/en/">
  <link rel="alternate" hreflang="x-default" href="${ORIGIN}/">
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="Codex Usage Bar">
  <meta property="og:title" content="${escape(t.title)}">
  <meta property="og:description" content="${escape(t.description)}">
  <meta property="og:url" content="${ORIGIN}${t.path}">
  <meta property="og:locale" content="${locale === 'en' ? 'en_US' : 'zh_CN'}">
  <meta property="og:locale:alternate" content="${locale === 'en' ? 'zh_CN' : 'en_US'}">
  <meta property="og:image" content="${ORIGIN}/assets/icon-512.png?v=quota-orbit-20261003">
  <meta name="twitter:card" content="summary">
  <link rel="icon" href="/assets/favicon.svg?v=quota-orbit-20261003" type="image/svg+xml">
  <link rel="apple-touch-icon" href="/assets/apple-touch-icon.png?v=quota-orbit-20261003">
  <link rel="manifest" href="${t.path}manifest.webmanifest">
  <link rel="preload" href="/assets/fonts/${locale === 'en' ? 'instrument-serif' : 'noto-serif-sc'}.woff2" as="font" type="font/woff2" crossorigin>
  <link rel="preload" href="/assets/fonts/manrope.woff2" as="font" type="font/woff2" crossorigin>
  <script src="/theme-bootstrap.js?v=20261003b"></script>
  <link rel="stylesheet" href="/styles.css?v=20261003b">
  <script type="application/ld+json">${structured}</script>
  <script type="module" src="/app.js?v=20261003b"></script>
</head>
<body>
  <a class="skip-link" href="#main">${t.skip}</a>
  <header class="site-header wrap">
    <a class="brand" href="${t.path}" aria-label="Codex Usage Bar">${mark()}<span>Codex Usage Bar</span></a>
    <nav aria-label="${locale === 'en' ? 'Main navigation' : '主导航'}">
      <a class="section-nav" href="#widgets">${t.navWidgets}</a>
      <a class="section-nav" href="#start">${t.navStart}</a>
      <a class="language-link" href="${t.otherPath}" lang="${t.otherLang}" hreflang="${t.otherLang}" aria-label="${t.languageLabel}">${t.language}</a>
      <button class="theme-toggle" type="button" aria-label="${t.dark}" hidden>${icon('moon', 'moon')}${icon('sun', 'sun')}</button>
    </nav>
  </header>
  <main id="main" class="wrap">
    <section class="hero" aria-labelledby="hero-title">
      <div class="hero-copy">
        <h1 id="hero-title">${t.heading.map((s, i) => `<span${i === 2 ? ' class="accent"' : ''}>${escape(s)}</span>`).join('')}</h1>
        <p class="intro">${lines(t.intro)}</p>
        <div class="hero-actions">${download(t)}<a class="source-link" href="${SOURCE}">${t.source}${icon('arrow')}</a></div>
        <p class="compatibility">${t.compatibility}</p>
      </div>
      <figure class="hero-stage" aria-label="${t.preview}">
        <div class="orbits" aria-hidden="true"><i></i><i></i><i></i></div>
        <div class="menu-preview" aria-hidden="true"><span>${mark()}<b data-demo="menu">Codex 64%</b></span><span class="system-icons">${icon('wifi')}${icon('search')}${icon('sliders')}<span>Mon 10:41</span></span></div>
        <div class="quota-card">
          <div class="quota-brand">${mark()}<strong data-demo="name">Codex</strong></div>
          <div class="provider-picker segmented" role="group" aria-label="${t.providerLabel}">
            <button type="button" data-provider-choice="codex" aria-pressed="true">Codex</button>
            <button type="button" data-provider-choice="kimi" aria-pressed="false">Kimi</button>
          </div>
          <div class="quota-readout" aria-live="polite" aria-atomic="true">
            <div class="quota-window"><span data-demo="primary">${t.weekly}</span><div class="quota-values"><strong data-demo="used">64%</strong><span data-demo="remaining">${t.remaining.replace('{value}', '36')}</span></div><progress data-progress="primary" value="64" max="100" aria-label="${t.weekly}">64%</progress></div>
            <div class="quota-window weekly-window" hidden><span>${t.weekly}</span><div class="quota-values"><strong>35%</strong></div><progress value="35" max="100" aria-label="${t.weekly}">35%</progress></div>
            <div class="quota-window"><span>${t.fiveHour}</span><div class="quota-values"><strong data-demo="fiveHour">45%</strong></div><progress data-progress="fiveHour" value="45" max="100" aria-label="${t.fiveHour}">45%</progress></div>
            <div class="reset-line">${icon('clock')}<span data-demo="reset">${t.reset}</span></div>
          </div>
        </div>
        <small class="illustrative">${t.illustrative}</small>
        <figcaption>${t.caption}</figcaption>
      </figure>
    </section>
    <section id="widgets" class="widgets-section" aria-labelledby="widget-title">
      <div class="section-heading"><h2 id="widget-title">${lines(t.widgetHeading)}</h2><p>${lines(t.widgetIntro)}</p></div>
      <div class="widget-stage">
        <div class="widgets-display">
          <div class="widget widget-small" data-size="small" aria-label="${t.small}"><div class="widget-brand">${mark()}<b data-demo="name">Codex</b></div>${ring('small-ring')}<span class="widget-remaining" data-demo="remaining">${t.remaining.replace('{value}', '36')}</span></div>
          <div class="widget widget-medium" data-size="medium" aria-label="${t.medium}"><div class="widget-brand">${mark()}<b data-demo="name">Codex</b></div><div class="medium-content">${ring('medium-ring')}<dl><div><dt data-demo="primary">${t.weekly}</dt><dd data-demo="used">64%</dd></div><div><dt>${t.remainingLabel}</dt><dd data-demo="remainingValue">36%</dd></div><div><dt>${t.resets}</dt><dd data-demo="days">${t.threeDays}</dd></div></dl></div></div>
        </div>
        <div class="size-control"><span>${t.sizes}</span><div class="segmented" role="group" aria-label="${t.widgetLabel}"><button type="button" data-size-choice="small" aria-pressed="true">${t.small}</button><button type="button" data-size-choice="medium" aria-pressed="false">${t.medium}</button></div></div>
        <small class="widget-illustrative">${t.illustrative}</small>
      </div>
      <div class="principles">${t.principles.map(([h, ...p]) => `<div><h3>${escape(h)}</h3><p>${lines(p)}</p></div>`).join('')}</div>
    </section>
    <section id="start" class="setup-section" aria-labelledby="setup-title">
      <h2 id="setup-title"><span>${t.setupHeading[0]}</span><span class="accent">${t.setupHeading[1]}</span></h2>
      <ol class="steps">${t.steps.map(([h, p], i) => `<li><span class="step-number">0${i + 1}</span><div><h3>${escape(h)}</h3><p>${escape(p)}</p></div></li>`).join('')}</ol>
    </section>
    <section class="faq-section" aria-labelledby="faq-title"><h2 id="faq-title">${t.faqHeading.split('\n').map(s => `<span>${escape(s)}</span>`).join('')}</h2><div class="faqs">${t.faqs.map(([q, a]) => `<details><summary>${escape(q)}<span class="plus" aria-hidden="true"></span></summary><p>${escape(a)}</p></details>`).join('')}</div></section>
    <section class="closing"><h2>${t.closing}</h2>${download(t, 'button-blue')}</section>
  </main>
  <footer class="site-footer wrap"><div class="footer-brand"><a href="${t.path}">${mark()}Codex Usage Bar</a><span>${t.independent}</span></div><div class="footer-links"><a href="${SOURCE}">GitHub</a><a href="${CENTER}">${t.downloadCenter}</a><span>© 2026 CMMUU</span></div><p class="release-info" aria-live="polite"></p></footer>
</body>
</html>
`;
  return { html, jsonHash };
}

export function previewContent() {
  return JSON.stringify({ previews, locales: Object.fromEntries(Object.entries(locales).map(([key, t]) => [key, Object.fromEntries(['weekly', 'monthly', 'remaining', 'reset', 'kimiReset', 'threeDays', 'twelveDays', 'light', 'dark', 'latest'].map(k => [k, t[k]]))])) });
}
