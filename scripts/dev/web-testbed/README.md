# Web testbed harness

Side-by-side live testing of the web frontends against a running gateway
(gateway must be up at 127.0.0.1:42617).

| Port | Serves | Notes |
|---|---|---|
| 8080 | `web-wasm-poc/` (Rust/Dioxus wasm) | token injected on `/api/*` |
| 8081 | `web/dist/` (fresh React build) | `/​_app/*` prefix-strip is mandatory (see below) |

## Use (always as-is)

From the repo root, with the pairing token at `reviews/.poctoken` (gitignored):

```
scripts/dev/web-testbed/start.sh
```

Both proxies send `Cache-Control: no-store` — stale-cache debugging is not
needed; a plain refresh is enough. `auth.html` (on either origin) stores a
token in localStorage for the app's client-side route guard.

## Why /_app/* matters

The React build references assets under `/_app/` (vite base). Without the
`uri strip_prefix /_app` + `file_server root web/dist` route, the SPA fallback
answers asset requests with `index.html` (text/html MIME); module scripts
enforce strict MIME checking and the app never boots — a blank page.
