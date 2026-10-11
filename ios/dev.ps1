# Run `xtool dev` in WSL against the phone plugged into Windows.
#
#   .\dev.ps1
#
# The phone stays on the Windows side: xtool talks to the usbmuxd that comes
# with Apple Devices (or iTunes) through Support/usbmuxd-relay.py. Passing the
# USB device into WSL with usbipd also connects, but the upload of the app
# stalls partway.
#
# Anything on the command line is passed on to `xtool dev`.
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$XtoolArgs
)

$ErrorActionPreference = 'Stop'
$UsbmuxdPort = 27015
$Socket = '/tmp/usbmuxd-win'

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
    throw 'node not found on PATH. The relay uses it to reach the Windows usbmuxd.'
}
if (-not (Get-NetTCPConnection -LocalPort $UsbmuxdPort -State Listen -ErrorAction SilentlyContinue)) {
    throw "Nothing is listening on 127.0.0.1:$UsbmuxdPort. Install Apple Devices from the Microsoft Store, plug in the phone, and unlock it."
}

function ConvertTo-WslPath([string]$Path) {
    wsl wslpath -a ($Path -replace '\\', '/')
}

$relayScript = ConvertTo-WslPath "$PSScriptRoot\Support\usbmuxd-relay.py"
$wslNode = ConvertTo-WslPath $node.Source
# Without this, SwiftPM reads the Linux sqlite3.pc and zlib.pc and puts
# /usr/lib/x86_64-linux-gnu ahead of the iOS SDK on the linker's search path.
$pkgConfig = ConvertTo-WslPath "$PSScriptRoot\Support\pkgconfig"

wsl rm -f $Socket
$relay = Start-Process wsl -WindowStyle Hidden -PassThru `
    -ArgumentList "--exec python3 `"$relayScript`" $Socket `"$wslNode`""
try {
    $ready = $false
    foreach ($attempt in 1..20) {
        wsl test -S $Socket
        if ($LASTEXITCODE -eq 0) { $ready = $true; break }
        Start-Sleep -Milliseconds 500
    }
    if (-not $ready) { throw 'The usbmuxd relay did not start in WSL.' }

    wsl --cd $PSScriptRoot env "PKG_CONFIG_PATH=$pkgConfig" "USBMUXD_SOCKET_ADDRESS=UNIX:$Socket" xtool dev @XtoolArgs
    $exitCode = $LASTEXITCODE
} finally {
    wsl pkill -f usbmuxd-relay.py
    Stop-Process -Id $relay.Id -ErrorAction SilentlyContinue
}
exit $exitCode
