#!/bin/sh
# Test-harness proxy start (:8081, fresh React build): reads the paired
# bearer token from reviews/.poctoken and injects it into /api/* upstream
# requests. The /_app/* route is REQUIRED — the vite build references
# assets under /_app/ and without the prefix-strip route try_files serves
# index.html as JS MIME (strict module check = blank page). Run from repo root.
export POC_TOKEN="$(cat /zc/reviews/.poctoken)"
exec caddy run --config /zc/scripts/dev/web-testbed/Caddyfile.8081
