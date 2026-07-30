#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "$ROOT/.." && pwd)"
ABIS="${ANDROID_ABIS:-arm64-v8a armeabi-v7a x86_64}"
if [[ "${CLEAN_ANDROID_JNI:-0}" == 1 ]]; then
  rm -rf "$ROOT/build/android-jni"
fi
mkdir -p "$ROOT/build/android-jni"

for abi in $ABIS; do
  out="$ROOT/build/android-jni/$abi"
  mkdir -p "$out"
  found=0
  for artifact_dir in "$ROOT"/build/artifacts/"$abi"/*; do
    [[ -d "$artifact_dir" ]] || continue
    while IFS= read -r library; do
      install -m 0644 "$library" "$out/"
      found=$((found + 1))
    done < <(find "$artifact_dir" -maxdepth 1 -type f -name 'lib*.so' ! -name 'libfrpc.so' ! -name 'libc++_shared.so' | sort)
  done

  # Every Luanti feature links against the NDK shared C++ runtime. Keep one
  # ABI-matching copy in the base APK so every independently delivered engine
  # split can load without bundling the same runtime seventeen times.
  cxx_runtime="$(find "$ROOT/build/artifacts/$abi" -mindepth 2 -maxdepth 2 -type f -name 'libc++_shared.so' -print -quit)"
  if [[ -n "$cxx_runtime" ]]; then
    install -m 0644 "$cxx_runtime" "$out/libc++_shared.so"
  else
    echo "warning: libc++_shared.so not found for $abi; engine loading will fail" >&2
  fi

  frpc="$REPO/tunnel/build/android-$abi/libfrpc.so"
  if [[ -f "$frpc" ]]; then
    install -m 0755 "$frpc" "$out/libfrpc.so"
  else
    echo "warning: libfrpc.so not found for $abi; release packaging will fail" >&2
  fi
  echo "synced $found $abi engine libraries and shared runtime to $out"
done
