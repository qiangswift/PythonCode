# Telegram System DNS

RootHide tweak for Telegram `ph.telegra.Telegraph` 12.9.3. It adds a **Use
system DNS** switch to the Proxy screen and simplifies the home screen.

When enabled, proxy hostnames that Telegram would resolve through its universal
Google DNS resolver are instead passed to the existing native iOS resolver.
The behavior applies to both SOCKS5 and MTProxy hostnames. Numeric proxy IPs are
unchanged, and normal Telegram datacenter IP connections are not redirected.

The implementation follows the open-source Swiftgram behavior in
`TelegramCore/Network.swift` and `MtProtoKit/MTTcpConnection.m`; no Swiftgram
binary code or assets are redistributed.

On the Telegram home screen, the bottom Contacts / Calls / Chats / Settings tab
bar and the search control are hidden. A replacement `+` button in the top-right
opens Telegram's existing account settings controller, so the hidden Settings
tab remains accessible without constructing a parallel settings screen.

## Build

```sh
make clean package THEOS_PACKAGE_SCHEME=roothide
```

Opening Telegram's proxy screen is required for the switch UI. The setting is
stored locally and affects subsequent proxy hostname resolutions. Compilation
does not constitute on-device UI or network verification.
