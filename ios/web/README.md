# DWG viewer (web)

The DWG half of the iOS app: `@mlightcad/cad-simple-viewer` plus the LibreDWG wasm parser,
built to a folder the app ships in its bundle.

```bash
npm ci
npm run build          # → dist/
./build-for-ios.sh     # → copies dist/ into the app's resources
```

## Why this runs in a web view

DWG has no usable open-source native parser. LibreDWG (GPL-3.0) is the only real option,
and its wasm build already works, so the iOS app serves this bundle over a private URL
scheme and hands it the drawing bytes.

## The page contract

`src/main.js` talks to Swift through `webkit.messageHandlers.cadEvents`:

| message | meaning |
|---|---|
| `{event:"ready"}` | the engine is up |
| `{event:"loading"}` | a drawing is being converted |
| `{event:"activated"}` | the document is open |
| `{event:"rendered", ms}` | the first frame is drawn |
| `{event:"error", message}` | something failed; the app shows it |

It fetches the drawing from `./__dwg__`, which the app's `WKURLSchemeHandler` answers, so
no multi-megabyte base64 blob ever goes through a URL.

## Two details that are easy to get wrong

- `base: './'` in `vite.config.js`, because a `WKURLSchemeHandler` has no server root.
- The worker scripts and the wasm have to sit in `assets/` under their bare names, with
  `application/wasm` and `text/javascript` MIME types, or WebKit refuses to stream-compile
  the wasm. `vite.config.js` copies them there after the bundle is written.
