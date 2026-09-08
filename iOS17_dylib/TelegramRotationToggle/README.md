# Telegram / Swiftgram Rotation Toggle

An iOS 17 jailbreak tweak for Telegram (`ph.telegra.Telegraph`) and Swiftgram
(`app.swiftgram.ios`). Every conversation header receives a lock button directly
to the left of the contact or group avatar.

- Unlocked icon: the app keeps its original gravity-based rotation behavior.
- Locked icon: the app immediately returns to portrait and remains portrait-only.
- The setting is persisted independently inside each app's sandbox.
- Default state is locked. Tap the unlocked/locked icon to restore or disable
  the app's original gravity-based rotation behavior.

The implementation was informed by static analysis of user-supplied decrypted
Telegram 12.9.3 and Swiftgram 12.9.2 binaries. The IPAs are not distributed.

Version 1.0.2 installs the chat-controller hooks when TelegramUIFramework is
actually loaded. This avoids the one-shot startup race caused by Swift classes
that are not yet registered when the tweak constructor runs.

Version 1.0.3 also detects ChatControllerImpl from the UIViewController
lifecycle that Telegram calls through `super`. This provides a path independent
of direct Swift-class hooking, and uses SF Symbols if packaged icons cannot be
resolved in a roothide path.

Version 1.0.4 binds the toggle through UIButton's own UIAction. The visible
fallback button therefore no longer depends on injecting an Objective-C action
selector into the late-loaded Swift chat-controller class.

Version 1.0.5 installs the control as an actual rightBarButtonItem instead of a
window overlay. Telegram rewrites that array during chat-state updates, so the
UINavigationItem setter keeps the toggle appended after Telegram's own items.

Version 1.0.6 removes the custom UIButton view that Telegram's custom navigation
bar reserved space for but did not render or route touches to. It now uses a
standard image UIBarButtonItem with a retained target/action and prepends it so
the item appears to the left of the avatar without stretching the avatar container.

Target environment: iOS 17 and Dopamine-compatible injection. The package is
scoped only to the two listed bundle identifiers and never injects SpringBoard.
