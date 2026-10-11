# CoffeeScheduler for iOS

A SwiftUI version of the scheduler that runs on the phone. It is built with
[xtool](https://github.com/xtool-org/xtool), so it builds and installs from
Linux (or Windows via WSL) with no Mac or Xcode project.

## Layout

```
ios/
  Package.swift         App package; xtool packages its CoffeeScheduler product as the app
  xtool.yml             Bundle ID, product, Info.plist path
  Support/Info.plist    Merged into the generated Info.plist (ZIP document type for the share sheet)
  Sources/CoffeeScheduler/   SwiftUI app
  CoffeeCore/           Platform-independent package, tested on Linux
    Sources/CoffeeCore/      Scheduler, BeanConqueror parser, SQLite store
    Tests/CoffeeCoreTests/
```

`CoffeeCore` is a port of the web app's `src/lib` (scheduler, BC parser, bean
queries, schedule loader, freeze logic, import route). It uses the same SQLite
schema, so one `coffee.db` works in both apps. When the scheduling rules change
in TypeScript, change the Swift port and its tests too.

## Setup

1. Install the Swift toolchain, `usbmuxd`, and xtool, and run `xtool setup`
   (Apple ID login plus the Xcode.xip it turns into an iOS SDK). Follow
   xtool's [Linux install guide](https://github.com/xtool-org/xtool/blob/main/Documentation/xtool.docc/Installation-Linux.md).
2. Change `bundleID` in `xtool.yml` if you want a different one (xtool
   registers it under a per-account prefix). With a free Apple ID the install
   expires after 7 days and needs another `xtool dev`; with a paid membership
   it lasts a year.
3. Plug in the phone (Developer Mode on) and run:

   ```bash
   cd ios
   xtool dev
   ```

## Tests

```bash
cd ios/CoffeeCore
swift test        # needs libsqlite3-dev on Linux
```

CI (`.github/workflows/ios.yml`) runs these on Linux (Swift 6.4) and type-checks the app
against the iOS SDK on a macOS runner.

## Where the data lives

On first launch, pick a folder in iCloud Drive (Settings → Storage). The app
keeps `coffee.db` there:

- SQLite works on a local copy in the app's Application Support directory.
- After every change the local copy is written back to the iCloud folder, and
  when the app comes to the foreground it pulls the iCloud copy if it is newer.
  Both go through `NSFileCoordinator`.
- The database uses a rollback journal, not WAL, so the single file is always
  complete.

Why a picked folder rather than the app's own iCloud container: an iCloud
container needs the iCloud capability on the App ID, and xtool can't
provision it. It only knows a fixed list of capabilities, and on each install
it removes App ID capabilities it doesn't recognize, so even enabling iCloud
by hand in the developer portal wouldn't stick. A folder picked through the
document picker needs no entitlement and works with a free Apple ID too.

To move data over from the web app, stop the dev server (the web app uses WAL,
so a copy taken while it runs can miss recent writes) and copy
`data/coffee.db` into the chosen iCloud Drive folder. The iOS app switches the
file to a rollback journal the first time it opens it.

## Importing from BeanConqueror

Export from BeanConqueror, then pick **Coffee** in the share sheet. The
app registers as a viewer for ZIP files (`CFBundleDocumentTypes` in
`Support/Info.plist`), and iOS hands the file to `onOpenURL`. If it doesn't
show in the share sheet, save the ZIP to Files and use **Settings → Import
BeanConqueror export**.

Imports behave like the web app's `/api/import`: BeanConqueror owns bean
details and brew history, and the app's own fields (rest days, queue order,
freeze plans, notes) are kept. One deliberate difference: when the export
has no roast date for a bag, the iOS import keeps the one already stored (for
example, one entered in the app); the web import clears it.

## Not ported yet

The app shows the schedule, the bean queue, each bag's detail, and the two
global settings, and can edit a bag's settings and freeze or thaw it. Queue
order, roaster defaults, skip days, consumption overrides, and publishing are
only in the web app for now (tracked in issue #6). All of them are already
stored in the shared database and are honored by the iOS schedule.
