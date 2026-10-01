#!/bin/sh
# Test-harness proxy start (:8080, PoC): reads the paired bearer token from
# reviews/.poctoken and injects it into /api/* upstream requests so a fresh
# browser origin (no localStorage) can view the page. Run from repo root.
export POC_TOKEN="$(cat /zc/reviews/.poctoken)"
exec caddy run --config /zc/scripts/dev/web-testbed/Caddyfile.8080
