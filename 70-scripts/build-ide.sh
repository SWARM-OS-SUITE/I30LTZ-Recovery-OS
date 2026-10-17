#!/usr/bin/env bash
# Build the I30LTZ IDE (Flutter, Linux release bundle) as a NORMAL user. Never run as root / never via sudo.
# Everything lives on the Recovery build partition: SDK in 25-toolchain/flutter-sdk, pub cache in 25-toolchain/pub-cache.
# Output: 30-source/i30ltz-ide/build/linux/x64/release/bundle/  (70-scripts/build.sh copies it into the ISO).
# First-time SDK setup (copy, do not move): cp -a /mnt/Lucy/30-source/flutter-sdk /mnt/recoverybuild/25-toolchain/flutter-sdk
set -euo pipefail
ROOT=/mnt/recoverybuild
[ "$(id -u)" -ne 0 ] || { echo "[IDE] run as a normal user, not root" >&2; exit 1; }
export FLUTTER_ROOT="$ROOT/25-toolchain/flutter-sdk" PUB_CACHE="$ROOT/25-toolchain/pub-cache"
export PATH="$FLUTTER_ROOT/bin:$PATH" FLUTTER_SUPPRESS_ANALYTICS=true CI=true
[ -x "$FLUTTER_ROOT/bin/flutter" ] || { echo "[IDE] Flutter SDK missing at $FLUTTER_ROOT (see header of this script)" >&2; exit 1; }
cd "$ROOT/30-source/i30ltz-ide"
flutter pub get
flutter analyze
flutter build linux --release
B=build/linux/x64/release/bundle
echo "[IDE] built: $PWD/$B ($(du -sh "$B" | cut -f1))"
missing=$(ldd "$B/i30ltz_ide" "$B"/lib/*.so 2>/dev/null | grep 'not found' | sort -u || true)
[ -z "$missing" ] || { echo "[IDE] missing libraries on this host:"; echo "$missing"; }
