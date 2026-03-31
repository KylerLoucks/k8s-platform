#!/bin/sh
set -e
# Browser-visible config: generated from env when the file is writable (Docker Compose).
# In Kubernetes, api-config.js is usually a read-only ConfigMap mount — leave it as-is.
TARGET=/usr/share/nginx/html/api-config.js
if [ ! -e "$TARGET" ] || [ -w "$TARGET" ]; then
  cat >"$TARGET" <<EOF
window.__API_BASE__ = "$API_PUBLIC_BASE";
window.__WS_BASE__ = "$WS_PUBLIC_BASE";
EOF
fi
exec "$@"
