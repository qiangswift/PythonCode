# Handoff

## 1.1.1

- Targets Telegram 12.9.3 (`ph.telegra.Telegraph`, executable `Telegram`).
- Adds a proxy-screen `Use system DNS` switch backed by `NSUserDefaults`.
- When enabled, redirects `MTDNS +resolveHostnameUniversal:port:` to Telegram's
  existing `+resolveHostnameNative:port:` implementation.
- RootHide and rootless packages are available. The rootless package is the
  build intended for TrollFools extraction/injection.
- Hides the home search control and bottom tab bar. A top-right `+` selects
  Telegram's existing account settings controller through its root tab
  controller.
- Static implementation and CI compilation can be verified here; actual proxy
  resolution and screen layout still require device testing.
