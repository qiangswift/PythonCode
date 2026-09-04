# QDReader Auto Check-in

An iOS tweak scoped to `m.qidian.QDReaderAppStore` and `m.qidian.QDReaderQiYe`.

Opening **My → Welfare Center** captures the app's own `getlogininfo` request,
then starts the bundled QDReader check-in script. The runner is independent of
the Welfare Center view controller: leaving the page does not cancel it. A new
entry while a run is active is ignored; completion is shown as an in-app alert.
The home-page **Check in / Claim benefits** action URL is also recognized.

The bookshelf navigation bar adds a native-style chapter-card balance and a
check-in icon immediately before the existing search button. Tapping the icon
runs the same verified check-in pipeline directly. The balance is refreshed
from QDReader's own signed **Mine** account request and its `ChapterCard`
response field. The tweak mirrors a request already created by QDReader, so it
neither synthesizes login headers nor stores account credentials. The rendered
Mine account cell remains a display-only fallback.

The tweak shows a start alert and a final alert. Diagnostic output is stored in
the app sandbox at `Documents/QDReaderAutoCheckin.log`. After a completed run,
the current date is recorded and later entries on the same day are skipped.

Native commercial splash ads, including cached first-party book promotions,
are rejected through QDReader's own no-ad launch predicates. Third-party splash
fallbacks keep their normal lifecycle and are closed through their skip path.

All upstream task modules are enabled by default: check-in, reward collection,
advertising jobs, extra daily jobs, lottery, weekly exchange, chapter-card
query, and recommendation-message handling.

## Attribution

The automation script is by [Yuheng0101/X – QDReader](https://github.com/Yuheng0101/X/tree/main/Tasks/QDReader).
See [NOTICE.md](NOTICE.md). This project adds only the jailbreak tweak trigger
and JavaScriptCore runtime bridge.

## Compatibility

- Tested target: QDReader App Store 5.9.474, iOS 17
- Package variants: rootful, rootless and roothide
- The tweak never injects SpringBoard

This is an unofficial personal automation project. Account and service risks
remain with the user, and upstream interfaces may change without notice.
