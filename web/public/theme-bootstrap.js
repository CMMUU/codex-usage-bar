(() => {
  const storageKey = "codex-usage-theme";
  let preference = "auto";

  try {
    const storedPreference = localStorage.getItem(storageKey);
    if (storedPreference === "light" || storedPreference === "dark") {
      preference = storedPreference;
    }
  } catch {
    // Storage can be unavailable in private or hardened browsing contexts.
  }

  const effectiveTheme =
    preference === "auto"
      ? matchMedia("(prefers-color-scheme: light)").matches
        ? "light"
        : "dark"
      : preference;

  document.documentElement.dataset.theme = effectiveTheme;
  document.documentElement.dataset.themePreference = preference;
  document.documentElement.style.colorScheme = effectiveTheme;

  const themeColor = document.querySelector('meta[name="theme-color"]');
  if (themeColor) {
    themeColor.content = effectiveTheme === "light" ? "#f4f7f5" : "#07090f";
  }
})();
