# CLAUDE.md

This repository is an iOS app. Everything is under `ios/`; see
`ios/README.md` for setup, the widget, Siri and how the data is stored.

## Commands

Run these in Linux or WSL.

```bash
cd ios/CoffeeCore && swift test   # Unit tests (needs libsqlite3-dev)
cd ios && xtool dev build         # Build the app against the iOS SDK
cd ios && xtool dev               # Build and install on a plugged-in phone
cd ios && ./lint.sh --fix         # Reformat and apply SwiftLint's own fixes
cd ios && ./lint.sh               # Check formatting and lint
```

On Windows, `ios\dev.ps1` builds in WSL and installs on a phone plugged into
Windows.

## Architecture

`ios/` is a SwiftUI app built with xtool (no Xcode project).

- `ios/CoffeeCore` is a platform-independent Swift package, tested on Linux:
  the scheduler, the BeanConqueror parser, the SQLite store and schema, and
  the layout the month view and widget share.
- `ios/Sources/CoffeeScheduler` is the app, `ios/Sources/CoffeeWidget` the
  home screen widget.

Put scheduling rules, schema changes and import behavior in CoffeeCore, with
tests, rather than in the app.

### Data

Bags and past brews are imported manually from a BeanConqueror iOS
application zip file export. The database is SQLite (`coffee.db`), kept in an
iCloud Drive folder the user picks, with a rollback journal rather than WAL.

### Date handling

All dates are ISO 8601 strings (`YYYY-MM-DD`). Do arithmetic through
`DateUtils`, which works in whole days so no time zone can shift a result.

### Linting

Swift is formatted with `swift format` and linted with SwiftLint: run
`./lint.sh --fix` in `ios/` (Linux or WSL) to reformat, then `./lint.sh` to
check. It fails on any finding, including the size and complexity caps in
`ios/.swiftlint.yml`. When new code trips a cap, split it up rather than
adding a `swiftlint:disable` comment. Compiler warnings are errors in both
packages.

### Testing patterns

Swift Testing in `ios/CoffeeCore/Tests`. Store tests open an in-memory
database; scheduler tests use a `makeBean()` helper with sensible defaults.
CI (`.github/workflows/ios.yml`) also renders screenshots and runs end-to-end
UI tests on an iOS Simulator.
