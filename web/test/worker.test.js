import assert from "node:assert/strict";
import test from "node:test";

import {
  normalizeRelease,
  normalizeCenterRelease,
  resolveLatestRelease,
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

test("normalizeRelease uses the current published fallback", () => {
  const release = normalizeRelease(null);

  assert.equal(release.tagName, "latest");
  assert.equal(release.name, "Latest release");
  assert.equal(
    release.downloadUrl,
    "https://downloads.cmmuu.com/projects/codex-usage-bar",
  );
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

const centerRelease = () => ({
  schemaVersion: 1, project: "codex-usage-bar", version: "v0.4.2", publishedAt: "2026-09-30T12:00:00Z",
  assets: { "macos-universal": {
    filename: "Codex-Usage-Bar-v0.4.2-universal.dmg", channel: "hk", hkAvailable: true,
    size: 1234, sha256: "a".repeat(64),
    downloadUrl: "https://downloads.cmmuu.com/download/codex-usage-bar/latest/macos-universal",
    fileUrl: "https://files.cmmuu.com/releases/codex-usage-bar/v0.4.2/Codex-Usage-Bar-v0.4.2-universal.dmg",
  } },
});

test("center release validates project, exact version, immutable URL and completeness", () => {
  assert.equal(normalizeCenterRelease(centerRelease()).source, "center");
  for (const mutate of [
    data => { data.project = "serylane"; },
    data => { data.assets["macos-universal"].filename = "Codex-Usage-Bar-v0.4.1-universal.dmg"; },
    data => { data.assets["macos-universal"].fileUrl = "https://example.com/app.dmg"; },
    data => { data.assets["macos-universal"].hkAvailable = false; },
    data => { data.assets.extra = {}; },
  ]) {
    const data = centerRelease(); mutate(data);
    assert.throws(() => normalizeCenterRelease(data));
  }
});

test("center is primary and does not query GitHub after success", async () => {
  const requests = [];
  const release = await resolveLatestRelease(async url => {
    requests.push(url); return Response.json(centerRelease());
  });
  assert.equal(release.source, "center");
  assert.equal(requests.length, 1);
  assert.equal(requests[0], "https://downloads.cmmuu.com/api/projects/codex-usage-bar/releases/latest");
});

test("center failure uses independent official GitHub asset", async () => {
  const requests = [];
  const release = await resolveLatestRelease(async url => {
    requests.push(url);
    if (url.startsWith("https://downloads.")) return new Response(null, { status: 503 });
    return Response.json({ tag_name: "v0.4.2", draft: false, prerelease: false, assets: [{
      name: "Codex-Usage-Bar-v0.4.2-universal.dmg", size: 1234,
      browser_download_url: "https://github.com/CMMUU/codex-usage-bar/releases/download/v0.4.2/Codex-Usage-Bar-v0.4.2-universal.dmg",
    }] });
  });
  assert.equal(requests.length, 2);
  assert.equal(release.source, "github");
  assert.ok(release.downloadUrl.startsWith("https://github.com/"));
});

test("unavailable or oversized metadata never invents a current version", async () => {
  const release = await resolveLatestRelease(async () => new Response("x".repeat(256 * 1024 + 1)));
  assert.equal(release.source, "fallback");
  assert.equal(release.tagName, "latest");
  assert.equal(release.downloadUrl, "https://downloads.cmmuu.com/projects/codex-usage-bar");
});
