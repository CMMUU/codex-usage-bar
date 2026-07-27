import assert from "node:assert/strict";
import test from "node:test";

import {
  normalizeRelease,
  selectMacDownloadAsset,
} from "../src/worker.js";

test("selectMacDownloadAsset prefers a universal macOS DMG", () => {
  const asset = selectMacDownloadAsset([
    {
      name: "Codex-Usage-Bar-linux.zip",
      browser_download_url: "https://example.com/linux.zip",
      size: 10,
    },
    {
      name: "Codex-Usage-Bar-macOS-arm64.zip",
      browser_download_url: "https://example.com/arm64.zip",
      size: 20,
    },
    {
      name: "Codex-Usage-Bar-macOS-universal.dmg",
      browser_download_url: "https://example.com/universal.dmg",
      size: 30,
    },
  ]);

  assert.equal(asset.name, "Codex-Usage-Bar-macOS-universal.dmg");
});

test("selectMacDownloadAsset ignores checksum files", () => {
  const asset = selectMacDownloadAsset([
    {
      name: "Codex-Usage-Bar-macOS.zip.sha256",
      browser_download_url: "https://example.com/checksum",
    },
    {
      name: "Codex-Usage-Bar-macOS.zip",
      browser_download_url: "https://example.com/app.zip",
    },
  ]);

  assert.equal(asset.browser_download_url, "https://example.com/app.zip");
});

test("normalizeRelease returns a GitHub asset when one exists", () => {
  const release = normalizeRelease({
    tag_name: "v0.2.0",
    name: "Version 0.2.0",
    published_at: "2026-07-27T00:00:00Z",
    html_url: "https://github.com/CMMUU/codex-usage-bar/releases/tag/v0.2.0",
    assets: [
      {
        name: "Codex-Usage-Bar-macOS-arm64.zip",
        browser_download_url: "https://github.com/download/app.zip",
        size: 1234,
      },
    ],
  });

  assert.equal(release.tagName, "v0.2.0");
  assert.equal(release.downloadKind, "asset");
  assert.equal(release.downloadUrl, "https://github.com/download/app.zip");
  assert.equal(release.assetSize, 1234);
});

test("normalizeRelease falls back to the release page without an asset", () => {
  const release = normalizeRelease({
    tag_name: "v0.1.0",
    name: "Version 0.1.0",
    html_url: "https://github.com/CMMUU/codex-usage-bar/releases/tag/v0.1.0",
    assets: [],
  });

  assert.equal(release.downloadKind, "release");
  assert.equal(
    release.downloadUrl,
    "https://github.com/CMMUU/codex-usage-bar/releases/tag/v0.1.0",
  );
});
