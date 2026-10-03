export const DOWNLOAD = 'https://downloads.cmmuu.com/download/codex-usage-bar/latest/macos-universal';
export const SOURCE = 'https://github.com/CMMUU/codex-usage-bar';
export const CENTER = 'https://downloads.cmmuu.com/projects/codex-usage-bar';
export const ORIGIN = 'https://codex.cmmuu.com';

export const locales = {
  en: {
    lang: 'en', path: '/en/', otherPath: '/', otherLang: 'zh-Hans', language: '中文', languageLabel: '切换到中文',
    title: 'Codex Usage Bar — A little more room for your next idea',
    description: 'Keep Codex and Kimi quotas in your Mac menu bar and desktop widgets. Free, open source, and built for a quick glance. Download for macOS.',
    navWidgets: 'Widgets', navStart: 'Get started', skip: 'Skip to content',
    heading: ['A little more room', 'for your', 'next idea.'],
    intro: ['Keep Codex and Kimi quotas in your menu bar.', 'Usage, time to reset, and room to keep going.'],
    download: 'Download for macOS', source: 'View source', compatibility: 'Free & open source · macOS 13+ · Apple & Intel',
    preview: 'Interactive quota preview', providerLabel: 'Preview subscription', weekly: 'Weekly usage', monthly: 'Monthly usage', fiveHour: '5-hour usage',
    remaining: '{value}% remaining', reset: 'Resets in 3 days', kimiReset: 'Resets in 12 days', illustrative: 'Illustrative data', caption: 'A glance, then back to your flow.',
    widgetHeading: ['Your desktop.', 'A little more informed.'], widgetIntro: ['Your quota, quietly in view.', 'Small and medium widgets stay in step with the app.'],
    sizes: 'Preview sizes', small: 'Small', medium: 'Medium', widgetLabel: 'Widget preview size', remainingLabel: 'Remaining', resets: 'Resets', threeDays: 'In 3 days', twelveDays: 'In 12 days',
    principles: [
      ['Local by design.', 'Quota data stays on your Mac.', 'The website never asks for your account.'],
      ['One place. Both subscriptions.', 'Switch between Codex and Kimi, with the', 'quota windows your account provides.'],
    ],
    setupHeading: ['Three steps.', 'Then, just a glance.'],
    steps: [
      ['Install the app', 'Download the universal DMG and move the app to Applications.'],
      ['Connect your subscription', 'Sign in to Codex or Kimi Code on this Mac, then select it in the app.'],
      ['Make yourself at home', 'Keep it in the menu bar. Add a desktop widget on macOS 14 or later.'],
    ],
    faqHeading: 'A few useful details.',
    faqs: [
      ['Which versions of macOS are supported?', 'The menu bar app requires macOS 13 or later. Desktop widgets require macOS 14 or later. One universal download supports both Apple silicon and Intel Macs. The app can discover the Codex CLI bundled with the Codex desktop app, including on macOS 27.'],
      ['Does this website read my quota?', 'No. Everything shown here is illustrative data. The installed app uses your local Codex sign-in or Kimi Code credentials to request quota from the corresponding service. Not every account exposes the same quota windows; API-key accounts may not provide subscription quota.'],
      ['How do updates work?', 'Choose “Check for updates” in the app. Updates are delivered through the download center with signature verification. You can also download the latest version here at any time. The app refreshes quota about every five minutes; macOS controls widget refresh timing, so widgets may update later.'],
    ],
    closing: 'Keep your next idea moving.', independent: 'An independent tool by CMMUU', downloadCenter: 'Download center', latest: 'Latest release',
    light: 'Switch to light appearance', dark: 'Switch to dark appearance', notFound: 'A little off track.', notFoundBody: 'This page has moved, or does not exist.', home: 'Back to the website',
  },
  zh: {
    lang: 'zh-Hans', path: '/', otherPath: '/en/', otherLang: 'en', language: 'EN', languageLabel: 'Switch to English',
    title: 'Codex Usage Bar — 留点余量，给下一个好想法',
    description: '在 Mac 菜单栏与桌面小组件中查看 Codex 和 Kimi 订阅额度、剩余额度与重置时间。免费开源，支持 Apple 与 Intel 芯片。',
    navWidgets: '小组件', navStart: '开始使用', skip: '跳至正文',
    heading: ['留点余量，', '给下一个', '好想法。'],
    intro: ['在菜单栏里，轻松查看 Codex 与 Kimi 额度。', '用了多少、何时重置，心里有数。'],
    download: '下载 macOS 版', source: '查看源码', compatibility: '免费开源 · macOS 13+ · Apple 与 Intel 芯片',
    preview: '可交互的额度预览', providerLabel: '预览订阅', weekly: '周额度', monthly: '月额度', fiveHour: '5 小时额度',
    remaining: '剩余 {value}%', reset: '3 天后重置', kimiReset: '12 天后重置', illustrative: '示例数据', caption: '看一眼，继续专注。',
    widgetHeading: ['桌面上，', '多一份从容。'], widgetIntro: ['让额度，安静地待在视线里。', '小号与中号小组件，和应用保持同步。'],
    sizes: '预览尺寸', small: '小号', medium: '中号', widgetLabel: '小组件预览尺寸', remainingLabel: '剩余额度', resets: '重置时间', threeDays: '3 天后', twelveDays: '12 天后',
    principles: [
      ['本地优先。', '额度数据保存在你的 Mac 上。', '这个网页，无需登录任何账户。'],
      ['两种订阅，一个入口。', '在 Codex 与 Kimi 之间轻松切换，', '查看你的账户实际提供的额度窗口。'],
    ],
    setupHeading: ['三步之后，', '一眼就够。'],
    steps: [
      ['安装应用', '下载通用版 DMG，将应用拖入「应用程序」文件夹。'],
      ['连接你的订阅', '先在这台 Mac 上登录 Codex 或 Kimi Code，再在应用中选择对应订阅。'],
      ['放在顺手的地方', '留在菜单栏，或在 macOS 14 及以上版本添加桌面小组件。'],
    ],
    faqHeading: '有些细节，\n你也许想知道。',
    faqs: [
      ['支持哪些 macOS 版本？', '菜单栏应用支持 macOS 13 及以上版本，桌面小组件需要 macOS 14 及以上版本。通用安装包同时支持 Apple 与 Intel 芯片。应用可识别 Codex 桌面应用内置的 CLI，也适配了 macOS 27 下的相关查找路径。'],
      ['这个网页会读取我的额度吗？', '不会。网页上的数据都是展示用的示例。安装后的应用会使用本机 Codex 登录状态或 Kimi Code 凭据，向对应服务查询额度。不同账户提供的额度窗口可能不同，API Key 账户不一定提供订阅额度。'],
      ['如何获取更新？', '在应用中点击「检查更新」，即可通过下载中心获取并验证更新签名。也可以随时从这里下载最新版本。应用约每 5 分钟刷新额度；小组件的刷新时机由 macOS 调度，可能稍有延迟。'],
    ],
    closing: '让好想法，继续发生。', independent: '由 CMMUU 独立开发', downloadCenter: '下载中心', latest: '最新版本',
    light: '切换到浅色外观', dark: '切换到深色外观', notFound: '好像走远了一点。', notFoundBody: '这个页面已移动，或暂时不存在。', home: '返回官网',
  },
};

// Deliberately synthetic. Never read account data in the website.
export const previews = {
  codex: { name: 'Codex', primary: 'weekly', used: 64, fiveHour: 45, weekly: null, resetKey: 'reset', daysKey: 'threeDays' },
  kimi: { name: 'Kimi', primary: 'monthly', used: 21, fiveHour: 50, weekly: 35, resetKey: 'kimiReset', daysKey: 'twelveDays' },
};
