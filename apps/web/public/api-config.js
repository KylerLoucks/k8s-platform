/* Vite dev: empty → proxy / fallback. Docker Compose: entrypoint fills from API_PUBLIC_BASE / WS_PUBLIC_BASE. Helm: ConfigMap. */
window.__API_BASE__ = window.__API_BASE__ || "";
window.__WS_BASE__ = window.__WS_BASE__ || "";
