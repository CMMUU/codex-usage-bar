// Resolve the saved appearance before CSS paints. Storage may be blocked.
try {
  const saved = localStorage.getItem('codex-usage-theme');
  if (saved === 'dark' || saved === 'light') document.documentElement.dataset.theme = saved;
} catch { /* Light appearance remains available without storage. */ }
