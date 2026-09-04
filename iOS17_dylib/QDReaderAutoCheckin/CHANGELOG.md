# Changelog

## 1.5.7

- Permanently remove the bookshelf game entry and reject asynchronous attempts
  to add the same native button back to the navigation stack.
- Match the check-in control more closely to the native search button by
  reducing both its visible circle and icon.
- Refresh the chapter-card balance immediately when QDReader assigns its
  in-memory Mine/account models, without issuing any balance request.

## 1.5.6

- Added the bookshelf chapter-card balance and hid the game entry.
- Added a native Mine-account-cell fallback for the chapter-card value.
