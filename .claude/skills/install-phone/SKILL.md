---
name: install-phone
description: Build the iOS app and install it on the iPhone plugged into Windows, from WSL, by running ios/dev.ps1 through PowerShell interop. Use when asked to install, deploy, or put the app on the phone.
---

# Install on the phone from WSL

The phone is plugged into Windows, not WSL. Plain `xtool dev` in WSL can't
see it, so don't run that or ask whether the phone is connected. Run
`ios/dev.ps1` through Windows interop instead. The script relays the Windows
usbmuxd (from Apple Devices) into WSL, sets `PKG_CONFIG_PATH` to
`ios/Support/pkgconfig`, and runs `xtool dev` in WSL.

## Steps

1. If you haven't already checked the change, run the tests and lint first
   (see CLAUDE.md).
2. Install:

   ```bash
   cd /home/matt/projects/CoffeeScheduler/ios && powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$(wslpath -w $PWD/dev.ps1)" 2>&1 | grep -v "lld does not support" | tail -25
   ```

   Use a timeout of about 600000 ms. Extra arguments after the script path
   are passed on to `xtool dev`.
3. It worked when the output ends with `[Verifying] 100%`, after
   `Installing to device: <name>`.

## When it fails

- `Nothing is listening on 127.0.0.1:27015`: Apple Devices isn't running, or
  the phone is locked or unplugged. Ask the user to unlock the phone and open
  Apple Devices.
- `node not found on PATH`: the relay needs Node on the Windows `PATH`.
- Stuck at `Waiting for device to be connected...`: the phone is probably
  locked, or hasn't trusted this computer yet.
- `ld64.lld: ... libsqlite3.so: unhandled file type`: `PKG_CONFIG_PATH` wasn't
  set. This happens when `xtool dev` runs without the script.
- The upload stalls: the phone may have been passed into WSL with usbipd. Ask
  the user to run `usbipd unbind --busid <id>` as admin to give it back to
  Windows.

To build without installing, run this in WSL:
`cd ios && PKG_CONFIG_PATH=$PWD/Support/pkgconfig xtool dev build`.
