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
  Support/AppIcon.png   App icon (xtool.yml `iconPath`), rendered from AppIcon.svg
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

   If the link step fails with `libz.so: unhandled file type`, the host's
   `zlib1g-dev` or `libsqlite3-dev` is leaking in through pkg-config. Point
   SwiftPM at the overrides in `Support/pkgconfig` instead:

   ```bash
   PKG_CONFIG_PATH="$PWD/Support/pkgconfig" xtool dev
   ```

   On Windows, `.\dev.ps1` does all of this from PowerShell. The phone stays
   plugged into Windows, and `xtool dev` in WSL reaches it through the
   usbmuxd that comes with Apple Devices (Microsoft Store), relayed by
   `Support/usbmuxd-relay.py`. It needs Node on the Windows `PATH`. Don't pass
   the phone into WSL with usbipd: it connects, but the app upload stalls. If
   it is already shared that way, give it back to Windows first with
   `usbipd unbind --busid <id>` (as admin).

To change the icon, edit `Support/AppIcon.svg` and re-render it as a 1024×1024
PNG with no transparency, for example with headless Edge or Chrome:

```powershell
msedge --headless=new --hide-scrollbars --force-device-scale-factor=1 `
  --window-size=1024,1024 --screenshot="$PWD\Support\AppIcon.png" "$PWD\Support\AppIcon.svg"
```

## Tests

```bash
cd ios/CoffeeCore
swift test        # needs libsqlite3-dev on Linux
```

CI (`.github/workflows/ios.yml`) runs these on Linux (Swift 6.4) and type-checks the app
against the iOS SDK on a macOS runner. On an iOS Simulator it also:

- renders every screen over sample data, light and dark, and uploads the
  images as the `screenshots` artifact (`Tests/CoffeeSchedulerScreenshots`);
- runs end-to-end UI tests (`E2E/Tests`) that launch the app and tap through
  each feature. XCUITest needs an app target, which a Swift package can't
  declare, so CI generates a small Xcode project from `E2E/project.yml` with
  XcodeGen. It only wraps the same library xtool installs.

Both use the sample data in `Sources/CoffeeScheduler/SampleData.swift`. A
debug build launched with `-sample-data` opens it in memory with today pinned
to 2026-10-12, so every run starts from the same state.

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

Export from BeanConqueror, then pick **Coffee Scheduler** in the share sheet. The
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

The app shows the schedule, the bean queue, each bag's detail, and the
settings, and can edit a bag's settings, freeze or thaw it, reorder the
queue, mark skip days, set a day's consumption, and set rest days by
roaster, with a month view with roaster colours and a bag key. The web app's
runway summary (days of coffee, the bag in progress) is left off the phone's
schedule; `RunwaySummary` in CoffeeCore still computes it. Publishing is only
in the web app for now (tracked in issue #6).
