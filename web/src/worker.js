const GITHUB_OWNER = "CMMUU";
const GITHUB_REPOSITORY = "codex-usage-bar";
const GITHUB_RELEASE_API =
  `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/releases/latest`;
const CENTER = "https://downloads.cmmuu.com";
const PROJECT_PAGE = `${CENTER}/projects/codex-usage-bar`;
const CENTER_RELEASE_API = `${CENTER}/api/projects/codex-usage-bar/releases/latest`;
const RELEASE_FALLBACK = {
  tagName: "latest",
  name: "Latest release",
  publishedAt: null,
  downloadUrl: PROJECT_PAGE,
  downloadKind: "release",
  assetName: null,
  assetSize: null,
  releaseUrl:
    `https://github.com/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/releases/latest`,
};

const RELEASE_CACHE_TTL_SECONDS = 60;

const JSON_HEADERS = {
  "Cache-Control": "public, max-age=60, s-maxage=60",
  "Content-Type": "application/json; charset=utf-8",
  "X-Content-Type-Options": "nosniff",
};

export function selectMacDownloadAsset(assets = []) {
  const supported = assets.filter((asset) => {
    const name = String(asset?.name ?? "").toLowerCase();
    return (
      asset?.browser_download_url
      && !name.includes("sha256")
      && !name.includes("checksum")
      && (name.endsWith(".dmg") || name.endsWith(".zip") || name.endsWith(".pkg"))
    );
  });

  return supported
    .map((asset) => {
      const name = asset.name.toLowerCase();
      let score = 0;
      if (name.includes("mac") || name.includes("darwin")) score += 100;
      if (name.includes("universal")) score += 50;
      if (name.includes("arm64") || name.includes("aarch64")) score += 30;
      if (name.endsWith(".dmg")) score += 20;
      if (name.endsWith(".pkg")) score += 10;
      return { asset, score };
    })
    .sort((left, right) => right.score - left.score)[0]?.asset ?? null;
}

export function normalizeRelease(release) {
  if (!release || typeof release !== "object") {
    return RELEASE_FALLBACK;
  }

  const releaseUrl =
    typeof release.html_url === "string"
      ? release.html_url
      : RELEASE_FALLBACK.releaseUrl;
  const asset = selectMacDownloadAsset(release.assets);

  return {
    tagName:
      typeof release.tag_name === "string"
        ? release.tag_name
        : RELEASE_FALLBACK.tagName,
    name:
      typeof release.name === "string"
        ? release.name
        : RELEASE_FALLBACK.name,
    publishedAt:
      typeof release.published_at === "string" ? release.published_at : null,
    downloadUrl: asset?.browser_download_url ?? releaseUrl,
    downloadKind: asset ? "asset" : "release",
    assetName: asset?.name ?? null,
    assetSize: Number.isFinite(asset?.size) ? asset.size : null,
    releaseUrl,
  };
}

export function normalizeCenterRelease(data) {
  const tag = data?.version;
  if (data?.schemaVersion !== 1 || data?.project !== "codex-usage-bar"
      || !/^v\d+\.\d+\.\d+$/.test(tag ?? "")
      || Object.keys(data.assets ?? {}).join() !== "macos-universal") {
    throw new Error("Invalid download center release");
  }
  const asset = data.assets["macos-universal"];
  const filename = `Codex-Usage-Bar-${tag}-universal.dmg`;
  const downloadUrl = `${CENTER}/download/codex-usage-bar/latest/macos-universal`;
  if (asset?.filename !== filename || asset.channel !== "hk" || asset.hkAvailable !== true
      || !Number.isSafeInteger(asset.size) || asset.size <= 0 || asset.size > 64 * 1024 * 1024
      || !/^[a-f0-9]{64}$/.test(asset.sha256 ?? "")
      || asset.downloadUrl !== downloadUrl
      || asset.fileUrl !== `https://files.cmmuu.com/releases/codex-usage-bar/${tag}/${filename}`) {
    throw new Error("Invalid download center asset");
  }
  return {
    tagName: tag, name: `Codex Usage Bar ${tag}`, publishedAt: data.publishedAt ?? null,
    downloadUrl, downloadKind: "asset", assetName: filename, assetSize: asset.size,
    releaseUrl: PROJECT_PAGE, source: "center",
  };
}

async function fetchMetadata(url, headers, fetcher) {
  const response = await fetcher(url, { headers, signal: AbortSignal.timeout(8000) });
  if (!response.ok) throw new Error("Release metadata unavailable");
  const reader = response.body?.getReader();
  if (!reader) throw new Error("Empty release metadata");
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > 256 * 1024) throw new Error("Release metadata exceeds limit");
      chunks.push(value);
    }
  } finally {
    await reader.cancel();
  }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return JSON.parse(new TextDecoder().decode(bytes));
}

export async function resolveLatestRelease(fetcher = fetch) {
  try {
    return normalizeCenterRelease(await fetchMetadata(CENTER_RELEASE_API, { Accept: "application/json" }, fetcher));
  } catch {
    // GitHub is an independent fallback when the center cannot verify its current archive.
  }
  try {
    const release = await fetchMetadata(GITHUB_RELEASE_API, {
      Accept: "application/vnd.github+json", "User-Agent": "codex-usage-bar-worker",
      "X-GitHub-Api-Version": "2022-11-28",
    }, fetcher);
    if (!/^v\d+\.\d+\.\d+$/.test(release?.tag_name ?? "") || release.draft !== false || release.prerelease !== false) {
      throw new Error("Invalid GitHub release");
    }
    const normalized = normalizeRelease(release);
    const selected = selectMacDownloadAsset(release.assets);
    if (!Number.isSafeInteger(selected?.size) || selected.size <= 0 || selected.size > 64 * 1024 * 1024
        || !/^sha256:[a-f0-9]{64}$/.test(selected?.digest ?? "")
        || normalized.assetName !== `Codex-Usage-Bar-${release.tag_name}-universal.dmg`
        || normalized.downloadUrl !== `https://github.com/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/releases/download/${release.tag_name}/${normalized.assetName}`) {
      throw new Error("Invalid GitHub download");
    }
    return { ...normalized, source: "github" };
  } catch {
    return { ...RELEASE_FALLBACK, source: "fallback" };
  }
}

async function getLatestRelease(request, context) {
  const cache = caches.default;
  const cacheURL = new URL("/api/release", request.url);
  cacheURL.searchParams.set("bucket", String(Math.floor(Date.now() / (RELEASE_CACHE_TTL_SECONDS * 1000))));
  const cacheKey = new Request(cacheURL, { method: "GET" });
  const cached = await cache.match(cacheKey);
  if (cached) return request.method === "HEAD" ? new Response(null, cached) : cached;
  const release = await resolveLatestRelease();
  const response = Response.json(release, {
    headers: { ...JSON_HEADERS, ...(release.source === "center" ? {} : { "Cache-Control": "no-store" }) },
  });
  if (release.source === "center") context.waitUntil(cache.put(cacheKey, response.clone()));
  return request.method === "HEAD" ? new Response(null, response) : response;
}

export default {
  async fetch(request, env, context) {
    const url = new URL(request.url);

    if (url.pathname === "/api/release") {
      if (request.method !== "GET" && request.method !== "HEAD") {
        return Response.json(
          { error: "Method not allowed" },
          {
            status: 405,
            headers: {
              ...JSON_HEADERS,
              Allow: "GET, HEAD",
            },
          },
        );
      }
      return getLatestRelease(request, context);
    }

    if (url.pathname === "/api/health") {
      return Response.json(
        {
          ok: true,
          service: "codex-usage-bar",
        },
        {
          headers: {
            "Cache-Control": "no-store",
            "Content-Type": "application/json; charset=utf-8",
          },
        },
      );
    }

    if (url.pathname.startsWith("/api/")) {
      return Response.json(
        { error: "Not found" },
        { status: 404, headers: JSON_HEADERS },
      );
    }

    return env.ASSETS.fetch(request);
  },
};
