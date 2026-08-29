# Reeder Portrait Lock

A focused iOS tweak that locks Reeder 5 (`com.reederapp.5.iOS`) to portrait.
It injects only into Reeder and never injects into SpringBoard.

The implementation was informed by static analysis of a user-supplied,
decrypted Reeder 5.4.2 binary. The IPA and extracted application files are not
included in this repository.

## Compatibility

- iOS 15-17
- rootfull
- rootless (including Dopamine)
- roothide

After installation, fully close and reopen Reeder. No respring is required for
normal installation, although package managers may offer one.
