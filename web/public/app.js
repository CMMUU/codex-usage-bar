import { data } from '/preview-content.js?v=20261003b';

const root = document.documentElement;
const locale = root.lang === 'en' ? 'en' : 'zh';
const text = data.locales[locale];
const themeButton = document.querySelector('.theme-toggle');
const updateThemeLabel = () => {
  const dark = root.dataset.theme === 'dark';
  themeButton.setAttribute('aria-label', dark ? text.light : text.dark);
  document.querySelector('meta[name="theme-color"]').content = dark ? '#141822' : '#FAFBFE';
};
updateThemeLabel();
themeButton.hidden = false;
themeButton.addEventListener('click', () => {
  root.dataset.theme = root.dataset.theme === 'dark' ? 'light' : 'dark';
  try { localStorage.setItem('codex-usage-theme', root.dataset.theme); } catch { /* Appearance still changes for this page. */ }
  updateThemeLabel();
});

for (const button of document.querySelectorAll('[data-provider-choice]')) {
  button.addEventListener('click', () => {
    const provider = button.dataset.providerChoice;
    const sample = data.previews[provider];
    root.dataset.provider = provider;
    const values = {
      name: sample.name, menu: `${sample.name} ${sample.used}%`, primary: text[sample.primary],
      used: `${sample.used}%`, remaining: text.remaining.replace('{value}', 100 - sample.used),
      remainingValue: `${100 - sample.used}%`, fiveHour: `${sample.fiveHour}%`,
      reset: text[sample.resetKey], days: text[sample.daysKey],
    };
    for (const element of document.querySelectorAll('[data-demo]')) element.textContent = values[element.dataset.demo];
    for (const progress of document.querySelectorAll('[data-progress]')) {
      const used = progress.dataset.progress === 'primary' ? sample.used : sample.fiveHour;
      progress.value = used;
      progress.textContent = `${used}%`;
      if (progress.dataset.progress === 'primary') progress.setAttribute('aria-label', text[sample.primary]);
    }
    for (const ring of document.querySelectorAll('.ring-progress')) ring.setAttribute('stroke-dasharray', `${sample.used} 100`);
    document.querySelector('.weekly-window').hidden = sample.weekly === null;
    for (const choice of document.querySelectorAll('[data-provider-choice]')) choice.setAttribute('aria-pressed', String(choice === button));
  });
}
for (const button of document.querySelectorAll('[data-size-choice]')) {
  button.addEventListener('click', () => {
    root.dataset.widgetSize = button.dataset.sizeChoice;
    for (const choice of document.querySelectorAll('[data-size-choice]')) choice.setAttribute('aria-pressed', String(choice === button));
  });
}
const languageLink = document.querySelector('.language-link');
languageLink.addEventListener('click', () => {
  if (['#widgets', '#start'].includes(location.hash)) languageLink.hash = location.hash;
});

// Download works without JavaScript. The API can supply a verified GitHub fallback.
const trustedDownload = (url) => url === 'https://downloads.cmmuu.com/download/codex-usage-bar/latest/macos-universal'
  || url === 'https://downloads.cmmuu.com/projects/codex-usage-bar'
  || /^https:\/\/github\.com\/CMMUU\/codex-usage-bar\/releases\/download\/v\d+\.\d+\.\d+\/Codex-Usage-Bar-v\d+\.\d+\.\d+-universal\.dmg$/.test(url);
async function refreshRelease() {
  try {
    const response = await fetch('/api/release', { signal: AbortSignal.timeout(10000) });
    if (!response.ok) return;
    const release = await response.json();
    if (!/^v\d+\.\d+\.\d+$/.test(release.tagName) || !trustedDownload(release.downloadUrl)) return;
    for (const link of document.querySelectorAll('.download-link')) link.href = release.downloadUrl;
    document.querySelector('.release-info').textContent = `${text.latest} · ${release.tagName}`;
  } catch { /* The permanent download-center link remains usable. */ }
}
refreshRelease();
