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
  Sources/CoffeeWidget/      Home screen widget (xtool.yml `extensions`)
  Support/CoffeeWidget-Info.plist   Marks the extension as a WidgetKit one
  Support/AppGroup.entitlements     The App Group the app and widget share
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

## Linting

```bash
cd ios
./lint.sh          # check formatting and lint; every finding is an error
./lint.sh --fix    # reformat, and apply the fixes SwiftLint can make itself
```

`lint.sh` runs two tools (Linux or WSL), and CI runs the same script:

- `swift format`, which comes with the Swift toolchain, checks the layout
  against `.swift-format` (4 spaces, 150 columns). Run `./lint.sh --fix`
  before committing rather than laying code out by hand. Its output can
  change between Swift releases, so format with the toolchain CI uses (6.4).
- SwiftLint, a pinned and checksum-verified download. `.swiftlint.yml` holds
  the rules, including caps on size and complexity: cyclomatic complexity 10,
  50 lines per function, 60 per closure, 5 parameters, 250 lines per type and
  400 per file. Nothing is exempt: when code trips a cap, split it up rather
  than adding a `swiftlint:disable` comment.

[Periphery](https://github.com/peripheryapp/periphery) finds unused code. It
isn't part of `lint.sh` or CI: it has no Linux binary (build it from source
with `swift build -c release`), and its findings need judgement, since fields
mirrored from the web app's models show up as assign-only. To run it over the
app and CoffeeCore together, build with xtool first and point it at that
build's index:

```bash
cd ios
xtool dev build
periphery scan --skip-build --index-store-path .build/out
```

The compiler is strict as well: `Package.swift` in both packages turns
warnings into errors (deprecations excepted) and enables the `ExistentialAny`
and `MemberImportVisibility` upcoming features.

## Tests

```bash
cd ios/CoffeeCore
swift test        # needs libsqlite3-dev on Linux
```

CI (`.github/workflows/ios.yml`) lints and runs these on Linux (Swift 6.4) and
type-checks the app against the iOS SDK on a macOS runner. On an iOS Simulator it also:

- renders every screen over sample data and uploads the images as the `screenshots` artifact (`Tests/CoffeeSchedulerScreenshots`);
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

## Widget

**Coffee month** is a home screen widget (medium or large) that draws the
current month like the Schedule screen: a bar per bag, dashed bars for
skipped days and days with no coffee, today in gold. Tapping it opens the app.

A widget runs in its own sandbox and can't open the database, so the app
writes a JSON snapshot (`WidgetSnapshot` in CoffeeCore) into an App Group
container each time the schedule changes, then asks the widget to reload. The
widget also redraws itself just after midnight.

The App Group needs a one-time setup in the Apple developer portal when xtool
is signed in with an App Store Connect API key: in that mode xtool turns the
capability on but can't create the group or assign it, and the install fails
with "A valid provisioning profile for this executable was not found".

1. Run `xtool dev` once (it fails, but registers both App IDs).
2. In [Identifiers](https://developer.apple.com/account/resources/identifiers/list/applicationGroup),
   add an App Group with the ID `group.net.mattmargolis.CoffeeScheduler`.
3. Under App IDs, open each of the two that xtool made (their names start with
   "XTool" and end in `CoffeeScheduler` and `CoffeeScheduler CoffeeWidget`),
   choose **Configure** beside App Groups, tick the group, and save.
4. Run `xtool dev` again.

App Groups need a paid membership; xtool drops the entitlement on a free
Apple ID, and the widget then only says to open the app.

The widget target asks the linker for `_main` (`Package.swift`). An
extension starts at `NSExtensionMain`, so without that nothing refers to the
widget's code, it is left out of the binary, and signing fails with "Can't
find free space of LoadCommands for CodeSignature".

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
runway summary (days of coffee, the bag in progress) is deliberately left
off the phone, which opens straight on the calendar. Publishing is only in
the web app for now (tracked in issue #6).
