#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/scripts/validate-catalog.py"
ABIS="${ANDROID_ABIS:-arm64-v8a armeabi-v7a x86_64}"
python3 - "$ROOT/catalog.json" <<'PY' | while read -r version library; do
import json, sys
for item in json.load(open(sys.argv[1]))["engines"]:
    print(item["version"], item["library"])
PY
  for abi in $ABIS; do
    artifact="$ROOT/build/artifacts/$abi/$version/lib$library.so"
    packaged="$ROOT/build/android-jni/$abi/lib$library.so"
    if [[ "${SKIP_EXISTING:-1}" == 1 && ( -s "$artifact" || -s "$packaged" ) ]]; then
      echo "already built $abi Luanti $version"
      continue
    fi
    "$ROOT/scripts/build-version.sh" "$version" "$abi"
  done
done
