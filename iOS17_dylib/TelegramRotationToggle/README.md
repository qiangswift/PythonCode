# Telegram / Swiftgram Rotation Toggle

An iOS 17 jailbreak tweak for Telegram (`ph.telegra.Telegraph`) and Swiftgram
(`app.swiftgram.ios`). Every conversation header receives a lock button directly
to the left of the contact or group avatar.

- Unlocked icon: the app keeps its original gravity-based rotation behavior.
- Locked icon: the app immediately returns to portrait and remains portrait-only.
- The setting is persisted independently inside each app's sandbox.
- Default state is unlocked, preserving the original app behavior until changed.

The implementation was informed by static analysis of user-supplied decrypted
Telegram 12.9.3 and Swiftgram 12.9.2 binaries. The IPAs are not distributed.

Target environment: iOS 17 and Dopamine-compatible injection. The package is
scoped only to the two listed bundle identifiers and never injects SpringBoard.
