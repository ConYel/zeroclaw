#!/bin/bash
# Web testbed harness — serves the wasm PoC (:8080) and the fresh React
# dashboard (:8081) against the live gateway (:42617) for side-by-side
# testing. Run from the repo root. Requires reviews/.poctoken (pairing
# token; the proxies inject it as Authorization on /api/*).
set -euo pipefail
cd "$(dirname "$0")/../../.."

if [ ! -f reviews/.poctoken ]; then
    echo "Missing reviews/.poctoken — paste the pairing token there first." >&2
    exit 1
fi

podman rm -f skills-poc-proxy skills-react-proxy >/dev/null 2>&1 || true
podman run -d --name skills-poc-proxy --network=host -v .:/zc:ro docker.io/caddy:2-alpine sh /zc/scripts/dev/web-testbed/start-8080.sh >/dev/null
podman run -d --name skills-react-proxy --network=host -v .:/zc:ro docker.io/caddy:2-alpine sh /zc/scripts/dev/web-testbed/start-8081.sh >/dev/null
echo "PoC:      http://127.0.0.1:8080/  (wasm, base #0c0e12)"
echo "Dashboard: http://127.0.0.1:8081/  (fresh web/dist, /_app fixed)"
