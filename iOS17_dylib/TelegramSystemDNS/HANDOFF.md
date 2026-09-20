# Handoff

## 1.0.0

- Targets Telegram 12.9.3 (`ph.telegra.Telegraph`, executable `Telegram`).
- Adds a proxy-screen `Use system DNS` switch backed by `NSUserDefaults`.
- When enabled, redirects `MTDNS +resolveHostnameUniversal:port:` to Telegram's
  existing `+resolveHostnameNative:port:` implementation.
- RootHide-only packaging is requested.
- Static implementation and CI compilation can be verified here; actual proxy
  resolution and screen layout still require device testing.
