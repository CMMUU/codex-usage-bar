const GITHUB_OWNER = "CMMUU";
const GITHUB_REPOSITORY = "codex-usage-bar";
const GITHUB_RELEASE_API =
  `https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/releases/latest`;
const RELEASE_FALLBACK = {
  tagName: "v0.1.0",
  name: "Codex Usage Bar v0.1.0",
  publishedAt: null,
  downloadUrl:
    `https://github.com/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/releases/latest`,
  downloadKind: "release",
  assetName: null,
  assetSize: null,
  releaseUrl:
    `https://github.com/${GITHUB_OWNER}/${GITHUB_REPOSITORY}/releases/latest`,
};

const JSON_HEADERS = {
  "Cache-Control": "public, max-age=300, s-maxage=900, stale-while-revalidate=86400",
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

async function getLatestRelease(request, context) {
  const cache = caches.default;
  const cacheKey = new Request(new URL("/api/release", request.url), {
    method: "GET",
  });
  const cached = await cache.match(cacheKey);
  if (cached) {
    return cached;
  }

  let payload = RELEASE_FALLBACK;
  let source = "fallback";

  try {
    const response = await fetch(GITHUB_RELEASE_API, {
      headers: {
        Accept: "application/vnd.github+json",
        "User-Agent": "codex-usage-bar-worker",
        "X-GitHub-Api-Version": "2022-11-28",
      },
    });

    if (response.ok) {
      payload = normalizeRelease(await response.json());
      source = "github";
    }
  } catch {
    // A stable fallback keeps the download path usable during GitHub API outages.
  }

  const response = Response.json(
    { ...payload, source },
    { headers: JSON_HEADERS },
  );
  context.waitUntil(cache.put(cacheKey, response.clone()));
  return response;
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
