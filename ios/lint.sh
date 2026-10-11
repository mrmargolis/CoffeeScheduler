#!/usr/bin/env bash
# Check the Swift code's formatting (swift format) and lint it (SwiftLint),
# as CI does:
#
#   ./lint.sh            # every finding is an error
#   ./lint.sh --fix      # reformat, and apply SwiftLint's own corrections
#
# Linux only (WSL included), with `swift` on the PATH. The SwiftLint release
# binary is downloaded once to ~/.cache and checked against the SHA-256
# below; to upgrade, change the version and both checksums together. Rules
# and caps are in .swiftlint.yml; arguments are passed on to SwiftLint.
set -euo pipefail

VERSION=0.65.1
case "$(uname -m)" in
  x86_64)
    ARCH=amd64 SHA256=caeed6f4a679c35539ffaf124f6c4ab4a8416917f7d8796279dc52b74026059d ;;
  aarch64 | arm64)
    ARCH=arm64 SHA256=9ffa52f478e6d8eb485d37d14715ffac90abc81c58f3370d598bf75be05605f8 ;;
  *)
    echo "lint.sh: no SwiftLint build for $(uname -m)" >&2
    exit 1 ;;
esac

dir="${XDG_CACHE_HOME:-$HOME/.cache}/swiftlint-$VERSION-$ARCH"
# The static build needs no Swift toolchain on the machine.
bin="$dir/swiftlint-static"

if [ ! -x "$bin" ]; then
  mkdir -p "$dir"
  curl -fsSL -o "$dir/swiftlint.zip" \
    "https://github.com/realm/SwiftLint/releases/download/$VERSION/swiftlint_linux_$ARCH.zip"
  echo "$SHA256  $dir/swiftlint.zip" | sha256sum -c - >&2
  python3 -m zipfile -e "$dir/swiftlint.zip" "$dir"
  rm "$dir/swiftlint.zip"
  chmod +x "$bin"
fi

cd "$(dirname "$0")"
# The formatter comes with the Swift toolchain; .swift-format configures it.
# Keep this list in step with `included` in .swiftlint.yml.
sources=(Package.swift Sources Tests E2E CoffeeCore/Package.swift CoffeeCore/Sources CoffeeCore/Tests)

if [ "${1:-}" = --fix ]; then
  shift
  swift format format --in-place --recursive --parallel "${sources[@]}"
  exec "$bin" lint --fix "$@"
fi
swift format lint --strict --recursive --parallel "${sources[@]}"
exec "$bin" lint --strict "$@"
