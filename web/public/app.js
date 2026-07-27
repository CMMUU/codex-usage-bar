const translations = {
  en: {
    eyebrow: "Native macOS menu bar utility",
    headlineOne: "Your Codex limit.",
    headlineTwo: "One glance away.",
    heroDescription:
      "Stop digging through account menus. See weekly usage, remaining quota, and reset time from your menu bar or macOS widgets.",
    download: "Get for macOS",
    source: "View source",
    requirements: "macOS 13+ · Universal",
    license: "MIT licensed",
    featureOneTitle: "Instant visibility",
    featureOneBody:
      "Weekly usage and reset time, without breaking your flow.",
    featureTwoTitle: "Local by design",
    featureTwoBody:
      "Talks to your local Codex app-server. No copied tokens.",
    featureThreeTitle: "Widget-ready",
    featureThreeBody:
      "Keep usage visible on the desktop or in Notification Center.",
    popoverSwitchHint: "CLICK 中 / EN TO SWITCH",
    popoverPreviewLanguage: "App preview language",
    popoverPreviewAlt:
      "Codex Usage Bar in English with a Chinese and English language switch",
    widgetTitle: "Your usage.<br>Always in view.",
    widgetDescription:
      "Add Codex Usage Bar to your desktop or Notification Center. Choose a compact glance or a detailed weekly overview.",
    widgetLayoutTitle: "Two useful sizes",
    widgetLayoutBody:
      "Small for the essentials. Medium for the full weekly picture.",
    widgetSyncTitle: "Local snapshot sync",
    widgetSyncBody:
      "Usage stays on your Mac and the last available snapshot remains visible.",
    widgetSynced: "SYNCED LOCALLY",
    widgetPreviewLanguage: "Widget preview language",
    widgetSmallLabel: "SMALL",
    widgetMediumLabel: "MEDIUM",
    widgetUsedShort: "USED",
    widgetRemaining: "REMAINING",
    widgetWeeklyUsed: "WEEKLY USED",
    widgetReset: "RESET",
    widgetResetValue: "RESET JUL 31 · 18:00",
    widgetResetDate: "JUL 31 · 18:00",
    widgetUpdated: "UPDATED 15:42",
    widgetInstallTitle: "Add it in three steps.",
    widgetInstallOne:
      "Open Codex Usage Bar once and refresh your usage.",
    widgetInstallTwo:
      "Open Edit Widgets from the desktop or Notification Center.",
    widgetInstallThree:
      "Search for “Codex” and choose the small or medium layout.",
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
    themeAuto: "Follow system",
    themeLight: "Light",
    themeDark: "Dark",
  },
  zh: {
    eyebrow: "原生 macOS 菜单栏工具",
    headlineOne: "Codex 限额。",
    headlineTwo: "抬眼即见。",
    heroDescription:
      "不必再层层打开账户菜单。直接从菜单栏或 macOS 小组件查看周用量、剩余额度与重置时间。",
    download: "获取 macOS 版本",
    source: "查看源码",
    requirements: "macOS 13+ · Universal",
    license: "MIT 开源",
    featureOneTitle: "状态一目了然",
    featureOneBody: "周限额和重置时间常驻菜单栏，不打断当前工作。",
    featureTwoTitle: "本地优先",
    featureTwoBody: "连接本机 Codex app-server，不复制认证令牌。",
    featureThreeTitle: "原生小组件",
    featureThreeBody: "在桌面或通知中心持续掌握 Codex 用量。",
    popoverSwitchHint: "点击 中 / EN 切换",
    popoverPreviewLanguage: "应用界面预览语言",
    popoverPreviewAlt: "带有中英文切换按钮的 Codex Usage Bar 中文界面",
    widgetTitle: "Codex 用量。<br>始终在眼前。",
    widgetDescription:
      "将 Codex Usage Bar 添加到桌面或通知中心。可选择紧凑速览，或更完整的周限额视图。",
    widgetLayoutTitle: "两种实用尺寸",
    widgetLayoutBody: "小尺寸聚焦关键信息，中尺寸展示完整周用量。",
    widgetSyncTitle: "本地快照同步",
    widgetSyncBody: "用量数据保留在 Mac 本地，并持续展示最近一次可用快照。",
    widgetSynced: "本地已同步",
    widgetPreviewLanguage: "小组件预览语言",
    widgetSmallLabel: "小尺寸",
    widgetMediumLabel: "中尺寸",
    widgetUsedShort: "已用",
    widgetRemaining: "剩余",
    widgetWeeklyUsed: "本周已用",
    widgetReset: "重置时间",
    widgetResetValue: "重置 7月31日 · 18:00",
    widgetResetDate: "7月31日 · 18:00",
    widgetUpdated: "更新于 15:42",
    widgetInstallTitle: "三步添加小组件。",
    widgetInstallOne: "打开一次 Codex Usage Bar，并刷新用量。",
    widgetInstallTwo: "从桌面或通知中心进入“编辑小组件”。",
    widgetInstallThree: "搜索“Codex”，选择小尺寸或中尺寸布局。",
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
    themeAuto: "跟随系统",
    themeLight: "浅色",
    themeDark: "深色",
  },
};

const themeStorageKey = "codex-usage-theme";
const themePreferences = ["auto", "light", "dark"];
const copyNodes = document.querySelectorAll("[data-copy]");
const widgetCopyNodes = document.querySelectorAll("[data-widget-copy]");
const languageButton = document.querySelector("#language-toggle");
const popoverPreviewImage = document.querySelector("#popover-preview-image");
const popoverLanguageSwitcher = document.querySelector(
  "#popover-language-switch",
);
const popoverLanguageButtons = document.querySelectorAll(
  "[data-popover-locale]",
);
const widgetLanguageSwitcher = document.querySelector(
  "#widget-language-switch",
);
const widgetLanguageButtons = document.querySelectorAll(
  "[data-widget-locale]",
);
const themeButton = document.querySelector("#theme-toggle");
const themeLabel = document.querySelector("#theme-label");
const downloadButton = document.querySelector("#download-button");
const releaseVersion = document.querySelector("#release-version");
const systemTheme = matchMedia("(prefers-color-scheme: light)");

let currentLocale =
  localStorage.getItem("codex-usage-locale")
  ?? (navigator.language.toLowerCase().startsWith("zh") ? "zh" : "en");
let currentRelease = null;
let currentPopoverLocale = currentLocale;
let currentWidgetLocale = currentLocale;
let currentThemePreference =
  document.documentElement.dataset.themePreference ?? "auto";

function saveThemePreference(preference) {
  try {
    if (preference === "auto") {
      localStorage.removeItem(themeStorageKey);
    } else {
      localStorage.setItem(themeStorageKey, preference);
    }
  } catch {
    // Theme changes still apply for the current page when storage is unavailable.
  }
}

function updateThemeControl() {
  const key =
    currentThemePreference === "light"
      ? "themeLight"
      : currentThemePreference === "dark"
        ? "themeDark"
        : "themeAuto";
  const label = translations[currentLocale][key];
  themeLabel.textContent = label;
  themeButton.title = label;
  themeButton.setAttribute("aria-label", `${label} — ${translations[currentLocale].themeAuto}`);
  themeButton.dataset.preference = currentThemePreference;
}

function applyThemePreference(preference, persist = false) {
  currentThemePreference = themePreferences.includes(preference)
    ? preference
    : "auto";
  const effectiveTheme =
    currentThemePreference === "auto"
      ? systemTheme.matches
        ? "light"
        : "dark"
      : currentThemePreference;

  document.documentElement.dataset.theme = effectiveTheme;
  document.documentElement.dataset.themePreference = currentThemePreference;
  document.documentElement.style.colorScheme = effectiveTheme;

  const themeColor = document.querySelector('meta[name="theme-color"]');
  if (themeColor) {
    themeColor.content = effectiveTheme === "light" ? "#f4f7f5" : "#07090f";
  }

  if (persist) {
    saveThemePreference(currentThemePreference);
  }
  updateThemeControl();
}

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
  applyPopoverLocale(locale);
  applyWidgetLocale(locale);
  updateDownloadCopy();
  updateThemeControl();
}

function applyPopoverLocale(locale) {
  currentPopoverLocale = locale === "zh" ? "zh" : "en";

  if (popoverPreviewImage) {
    popoverPreviewImage.src =
      currentPopoverLocale === "zh"
        ? "/assets/usage-popover-zh-Hans.png"
        : "/assets/usage-popover-en.png";
    popoverPreviewImage.alt =
      translations[currentPopoverLocale].popoverPreviewAlt;
  }

  popoverLanguageSwitcher?.setAttribute(
    "aria-label",
    translations[currentPopoverLocale].popoverPreviewLanguage,
  );
  for (const button of popoverLanguageButtons) {
    const isActive = button.dataset.popoverLocale === currentPopoverLocale;
    button.setAttribute("aria-pressed", String(isActive));
  }
}

function applyWidgetLocale(locale) {
  currentWidgetLocale = locale === "zh" ? "zh" : "en";

  for (const node of widgetCopyNodes) {
    const key = node.dataset.widgetCopy;
    const value = translations[currentWidgetLocale][key];
    if (typeof value === "string") {
      node.textContent = value;
    }
  }

  widgetLanguageSwitcher?.setAttribute(
    "aria-label",
    translations[currentWidgetLocale].widgetPreviewLanguage,
  );
  for (const button of widgetLanguageButtons) {
    const isActive = button.dataset.widgetLocale === currentWidgetLocale;
    button.setAttribute("aria-pressed", String(isActive));
  }
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

for (const button of widgetLanguageButtons) {
  button.addEventListener("click", () => {
    applyWidgetLocale(button.dataset.widgetLocale);
  });
}

for (const button of popoverLanguageButtons) {
  button.addEventListener("click", (event) => {
    applyPopoverLocale(button.dataset.popoverLocale);
    if (event.detail > 0) {
      button.blur();
    }
  });
}

themeButton.addEventListener("click", () => {
  const currentIndex = themePreferences.indexOf(currentThemePreference);
  const nextPreference =
    themePreferences[(currentIndex + 1) % themePreferences.length];
  applyThemePreference(nextPreference, true);
});

systemTheme.addEventListener("change", () => {
  if (currentThemePreference === "auto") {
    applyThemePreference("auto");
  }
});

applyThemePreference(currentThemePreference);
applyLocale(currentLocale);
loadLatestRelease();
