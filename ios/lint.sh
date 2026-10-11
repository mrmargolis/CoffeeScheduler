#!/usr/bin/env bash
# Lint the Swift code with a pinned SwiftLint, as CI does:
#
#   ./lint.sh            # every warning is an error (--strict)
#   ./lint.sh --fix      # apply the corrections SwiftLint can make itself
#
# Linux only (WSL included). The release binary is downloaded once to
# ~/.cache and checked against the SHA-256 below; to upgrade, change the
# version and both checksums together. Rules and caps are in .swiftlint.yml.
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
if [ "${1:-}" = --fix ]; then
  shift
  exec "$bin" lint --fix "$@"
fi
exec "$bin" lint --strict "$@"
