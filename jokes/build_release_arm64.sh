#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUT_DIR="build/app/outputs/flutter-apk"
ARM64_APK="$OUT_DIR/app-arm64-v8a-release.apk"
FINAL_APK="$OUT_DIR/app-release.apk"
FINAL_SHA1="$OUT_DIR/app-release.apk.sha1"

flutter build apk --release --split-per-abi

[[ -f "$ARM64_APK" ]] || {
  echo "arm64-v8a APK not found: $ARM64_APK" >&2
  exit 1
}

find "$OUT_DIR" -maxdepth 1 \( -name 'app-armeabi-v7a-release.apk*' -o -name 'app-x86_64-release.apk*' \) -delete
cp "$ARM64_APK" "$FINAL_APK"
if [[ -f "$ARM64_APK.sha1" ]]; then
  cp "$ARM64_APK.sha1" "$FINAL_SHA1"
fi

echo "ARM64 release APK ready: $FINAL_APK"
