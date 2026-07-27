const translations = {
  en: {
    eyebrow: "Native macOS menu bar utility",
    headlineOne: "Your Codex limit.",
    headlineTwo: "One glance away.",
    heroDescription:
      "Stop digging through account menus. See weekly usage, remaining quota, and reset time directly from your menu bar.",
    download: "Get for macOS",
    source: "View source",
    requirements: "macOS 13+ · Apple Silicon",
    license: "MIT licensed",
    featureOneTitle: "Instant visibility",
    featureOneBody:
      "Weekly usage and reset time, without breaking your flow.",
    featureTwoTitle: "Local by design",
    featureTwoBody:
      "Talks to your local Codex app-server. No copied tokens.",
    featureThreeTitle: "Quietly native",
    featureThreeBody:
      "A lightweight SwiftUI companion built for the macOS menu bar.",
    storyTitle: "Stay in flow.<br>Keep usage in sight.",
    storyBody:
      "Checking Codex usage used to mean opening the account menu, then opening usage details. This tiny app turns that repeated detour into a single click.",
    before: "BEFORE",
    beforeFlow: "Profile → Usage → Limits",
    now: "NOW",
    nowFlow: "One glance",
    openTitle: "Small tool. Open code.",
    openBody:
      "Inspect how it works, report an issue, or shape the next release.",
    openButton: "Explore on GitHub",
    footer: "Built to keep creators in flow.",
    downloadAsset: "Download {version}",
    downloadRelease: "Get {version} on GitHub",
  },
  zh: {
    eyebrow: "原生 macOS 菜单栏工具",
    headlineOne: "Codex 限额。",
    headlineTwo: "抬眼即见。",
    heroDescription:
      "不必再层层打开账户菜单。直接从菜单栏查看周用量、剩余额度与重置时间。",
    download: "获取 macOS 版本",
    source: "查看源码",
    requirements: "macOS 13+ · Apple 芯片",
    license: "MIT 开源",
    featureOneTitle: "状态一目了然",
    featureOneBody: "周限额和重置时间常驻菜单栏，不打断当前工作。",
    featureTwoTitle: "本地优先",
    featureTwoBody: "连接本机 Codex app-server，不复制认证令牌。",
    featureThreeTitle: "原生轻量",
    featureThreeBody: "专为 macOS 菜单栏打造的轻量 SwiftUI 应用。",
    storyTitle: "保持专注。<br>用量始终在眼前。",
    storyBody:
      "过去查看 Codex 用量，需要打开账户菜单，再进入用量详情。这个小工具把反复出现的操作缩短为一次点击。",
    before: "以前",
    beforeFlow: "用户名 → 剩余用量 → 限额",
    now: "现在",
    nowFlow: "抬眼即见",
    openTitle: "小工具，开放源码。",
    openBody: "查看实现、提交问题，或参与塑造下一个版本。",
    openButton: "前往 GitHub",
    footer: "为保持创造者专注而生。",
    downloadAsset: "下载 {version}",
    downloadRelease: "在 GitHub 获取 {version}",
  },
};

const copyNodes = document.querySelectorAll("[data-copy]");
const languageButton = document.querySelector("#language-toggle");
const downloadButton = document.querySelector("#download-button");
const releaseVersion = document.querySelector("#release-version");

let currentLocale =
  localStorage.getItem("codex-usage-locale")
  ?? (navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en");
let currentRelease = null;

function applyLocale(locale) {
  currentLocale = locale;
  document.documentElement.lang = locale === "zh" ? "zh-CN" : "en";
  document.title =
    locale === "zh"
      ? "Codex Usage Bar — 菜单栏里的周限额度"
      : "Codex Usage Bar — Your weekly limit at a glance";

  for (const node of copyNodes) {
    const key = node.dataset.copy;
    const value = translations[locale][key];
    if (typeof value !== "string") continue;
    if (value.includes("<br>")) {
      const [firstLine, secondLine] = value.split("<br>");
      node.replaceChildren(
        document.createTextNode(firstLine),
        document.createElement("br"),
        document.createTextNode(secondLine),
      );
    } else {
      node.textContent = value;
    }
  }

  languageButton.textContent = locale === "zh" ? "EN" : "中文";
  localStorage.setItem("codex-usage-locale", locale);
  updateDownloadCopy();
}

function updateDownloadCopy() {
  if (!currentRelease) return;
  const version = currentRelease.tagName ?? "latest";
  const key =
    currentRelease.downloadKind === "asset"
      ? "downloadAsset"
      : "downloadRelease";
  downloadButton.querySelector("span").textContent =
    translations[currentLocale][key].replace("{version}", version);
}

async function loadLatestRelease() {
  try {
    const response = await fetch("/api/release", {
      headers: { Accept: "application/json" },
    });
    if (!response.ok) return;

    const release = await response.json();
    if (!release?.downloadUrl || !release?.tagName) return;

    currentRelease = release;
    downloadButton.href = release.downloadUrl;
    releaseVersion.textContent = release.tagName;
    updateDownloadCopy();
  } catch {
    // Static GitHub fallback remains available when the release API is offline.
  }
}

languageButton.addEventListener("click", () => {
  applyLocale(currentLocale === "zh" ? "en" : "zh");
});

applyLocale(currentLocale);
loadLatestRelease();
