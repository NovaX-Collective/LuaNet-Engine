#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <version> [arm64-v8a|armeabi-v7a|x86_64]" >&2
  exit 64
fi
: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to an installed Android NDK}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$1"
ABI="${2:-${ANDROID_ABI:-arm64-v8a}}"
case "$ABI" in
  arm64-v8a)
    CLANG_TRIPLE="aarch64-linux-android"
    SYSROOT_TRIPLE="aarch64-linux-android"
    ;;
  armeabi-v7a)
    CLANG_TRIPLE="armv7a-linux-androideabi"
    SYSROOT_TRIPLE="arm-linux-androideabi"
    ;;
  x86_64)
    CLANG_TRIPLE="x86_64-linux-android"
    SYSROOT_TRIPLE="x86_64-linux-android"
    ;;
  *)
    echo "unsupported Android ABI: $ABI" >&2
    exit 64
    ;;
esac
readarray -t META < <(python3 - "$ROOT/catalog.json" "$VERSION" <<'PY'
import json, sys
catalog = json.load(open(sys.argv[1]))
item = next((x for x in catalog["engines"] if x["version"] == sys.argv[2]), None)
if not item:
    raise SystemExit(f"unsupported engine {sys.argv[2]}")
print(catalog["repository"])
print(item["tag"])
print(item["commit"])
print(item["library"])
PY
)
REPOSITORY="${META[0]}"
TAG="${META[1]}"
COMMIT="${META[2]}"
LIBRARY="${META[3]}"
GIT_CACHE_ROOT="${ENGINE_GIT_CACHE_ROOT:-$ROOT/.cache}"
CACHE="$GIT_CACHE_ROOT/luanti.git"
CACHE_LOCK="$GIT_CACHE_ROOT/luanti.lock"
WORK_ROOT="${ENGINE_WORK_ROOT:-$ROOT/build/work}"
OUTPUT="$ROOT/build/artifacts/$ABI/$VERSION"

mkdir -p "$ROOT/.cache" "$GIT_CACHE_ROOT"
exec 9>"$CACHE_LOCK"
flock 9
if [[ ! -d "$CACHE" ]]; then
  git init --bare "$CACHE"
  git -C "$CACHE" remote add origin "$REPOSITORY"
fi
git -C "$CACHE" remote set-url origin "$REPOSITORY"
for attempt in 1 2 3; do
  if git -C "$CACHE" fetch --force --depth 1 origin "refs/tags/$TAG:refs/tags/$TAG"; then
    break
  fi
  if [[ "$attempt" == 3 ]]; then
    echo "failed to fetch Luanti $TAG after $attempt attempts" >&2
    exit 66
  fi
  sleep "$((attempt * 5))"
done
ACTUAL="$(git -C "$CACHE" rev-parse "refs/tags/$TAG^{}")"
if [[ "$ACTUAL" != "$COMMIT" ]]; then
  echo "source verification failed: expected $COMMIT, got $ACTUAL" >&2
    exit 65
fi

mkdir -p "$WORK_ROOT"
SOURCE="$(mktemp -d "$WORK_ROOT/${VERSION}.XXXXXX")"
trap 'rm -rf "$SOURCE"' EXIT
git clone --quiet --no-checkout "$CACHE" "$SOURCE"
flock -u 9
git -C "$SOURCE" checkout -q --detach "$COMMIT"
git -C "$SOURCE" submodule update --init --depth 1
BUILD="$SOURCE/.luanet-build"

python3 "$ROOT/scripts/prepare-source.py" "$SOURCE" \
  --bridge "$ROOT/bridge/src/luanet_engine.cpp" --library "$LIBRARY"

DEPS_URL="https://github.com/luanti-org/luanti_android_deps/releases/download/latest/deps-lite.zip"
DEPS_SHA256="8d3a2d887a6b726fa260e623f1fabf7b2e94cf0c0ab952d998cfb69fbd635e1f"
DEPS_ARCHIVE="$ROOT/.cache/deps-lite-$DEPS_SHA256.zip"
DEPS="${ANDROID_DEPS_ROOT:-$ROOT/.cache/android-deps-$DEPS_SHA256}"
if [[ ! -d "$DEPS/$ABI" ]]; then
  mkdir -p "$DEPS"
  if [[ ! -f "$DEPS_ARCHIVE" ]]; then
    curl --fail --location --retry 3 "$DEPS_URL" --output "$DEPS_ARCHIVE.tmp"
    mv "$DEPS_ARCHIVE.tmp" "$DEPS_ARCHIVE"
  fi
  echo "$DEPS_SHA256  $DEPS_ARCHIVE" | sha256sum --check --status || {
    echo "Android dependency archive checksum mismatch" >&2
    exit 69
  }
  unzip -q "$DEPS_ARCHIVE" -d "$DEPS"
fi
mkdir -p "$SOURCE/android/native"
if [[ -d "$SOURCE/android/native/deps" && ! -L "$SOURCE/android/native/deps" ]]; then
  rmdir "$SOURCE/android/native/deps"
fi
ln -s "$DEPS" "$SOURCE/android/native/deps"
ABI_DEPS="$DEPS/$ABI"
SQLITE_DIR="$ABI_DEPS/SQLite"
IRRLICHT_REPOSITORY="https://github.com/minetest/irrlicht.git"
IRRLICHT_TAG="1.9.0mt0"
IRRLICHT_COMMIT="03ad637114ffb255f5b9d36c204072e8d263022f"
IRRLICHT_CACHE="$GIT_CACHE_ROOT/irrlichtmt.git"
IRRLICHT_ROOT="$ROOT/build/legacy-irrlicht/$IRRLICHT_COMMIT"
IRRLICHT_STUB_DIR="$ROOT/build/legacy-irrlicht/android-$ABI"
IRRLICHT_STUB_LIB="$IRRLICHT_STUB_DIR/libIrrlicht.a"
if [[ ! -d "$IRRLICHT_ROOT/include" ]]; then
  if [[ ! -d "$IRRLICHT_CACHE" ]]; then
    git init --bare "$IRRLICHT_CACHE"
    git -C "$IRRLICHT_CACHE" remote add origin "$IRRLICHT_REPOSITORY"
  fi
  git -C "$IRRLICHT_CACHE" remote set-url origin "$IRRLICHT_REPOSITORY"
  git -C "$IRRLICHT_CACHE" fetch --force --depth 1 origin "refs/tags/$IRRLICHT_TAG:refs/tags/$IRRLICHT_TAG"
  IRRLICHT_ACTUAL="$(git -C "$IRRLICHT_CACHE" rev-parse "refs/tags/$IRRLICHT_TAG^{}")"
  if [[ "$IRRLICHT_ACTUAL" != "$IRRLICHT_COMMIT" ]]; then
    echo "Irrlicht header verification failed: expected $IRRLICHT_COMMIT, got $IRRLICHT_ACTUAL" >&2
    exit 67
  fi
  IRRLICHT_SOURCE="$(mktemp -d "$WORK_ROOT/irrlicht.XXXXXX")"
  git clone --quiet --no-checkout "$IRRLICHT_CACHE" "$IRRLICHT_SOURCE"
  git -C "$IRRLICHT_SOURCE" checkout -q --detach "$IRRLICHT_COMMIT"
  mkdir -p "$IRRLICHT_ROOT"
  cp -a "$IRRLICHT_SOURCE/include" "$IRRLICHT_ROOT/"
  rm -rf "$IRRLICHT_SOURCE"
fi
if [[ ! -f "$IRRLICHT_STUB_LIB" ]]; then
  TOOLCHAIN_BIN="$(find "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" -mindepth 1 -maxdepth 1 -type d -print -quit)/bin"
  mkdir -p "$IRRLICHT_STUB_DIR"
  printf 'void luanet_irrlicht_stub(void) {}\n' > "$IRRLICHT_STUB_DIR/irrlicht_stub.c"
  "$TOOLCHAIN_BIN/${CLANG_TRIPLE}29-clang" -c "$IRRLICHT_STUB_DIR/irrlicht_stub.c" -o "$IRRLICHT_STUB_DIR/irrlicht_stub.o"
  "$TOOLCHAIN_BIN/llvm-ar" rcs "$IRRLICHT_STUB_LIB" "$IRRLICHT_STUB_DIR/irrlicht_stub.o"
fi

ZSTD_ARGS=()
if grep -q 'find_package(Zstd' "$SOURCE/src/CMakeLists.txt"; then
  TOOLCHAIN_BIN="$(find "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt" -mindepth 1 -maxdepth 1 -type d -print -quit)/bin"
  ZSTD_ROOT="$ABI_DEPS/Zstd"
  ZSTD_LIBRARY="$ZSTD_ROOT/libzstd.a"
  test -f "$ZSTD_ROOT/include/zstd.h" -a -f "$ZSTD_LIBRARY"
  ZSTD_ARGS=(-DZSTD_INCLUDE_DIR="$ZSTD_ROOT/include" -DZSTD_LIBRARY="$ZSTD_LIBRARY")
fi

declare -a CMAKE_ARGS=(
  -S "$SOURCE"
  -B "$BUILD"
  -G Ninja
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake"
  -DANDROID_ABI="$ABI"
  -DANDROID_PLATFORM=android-29
  -DANDROID_STL=c++_shared
  -DANDROID_SUPPORT_FLEXIBLE_PAGE_SIZES=ON
  -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_POSITION_INDEPENDENT_CODE=ON
  -DCMAKE_CXX_FLAGS="-I$IRRLICHT_ROOT/include"
  -DCMAKE_SHARED_LINKER_FLAGS="-Wl,-z,max-page-size=16384"
  -DCMAKE_DISABLE_FIND_PACKAGE_IrrlichtMt=ON
  -DIRRLICHT_INCLUDE_DIR="$IRRLICHT_ROOT/include"
  -DIRRLICHT_LIBRARY="$IRRLICHT_STUB_LIB"
  -DSQLITE3_INCLUDE_DIR="$SQLITE_DIR/include"
  -DSQLITE3_LIBRARY="$SQLITE_DIR/libsqlite3.a"
  -DSQLite3_INCLUDE_DIR="$SQLITE_DIR/include"
  -DSQLite3_LIBRARY="$SQLITE_DIR/libsqlite3.a"
  -DBUILD_CLIENT=OFF
  -DBUILD_SERVER=ON
  -DBUILD_UNITTESTS=OFF
  -DBUILD_BENCHMARKS=OFF
  -DENABLE_CURSES=OFF
  -DENABLE_CURL=ON
  -DENABLE_FREETYPE=OFF
  -DENABLE_GETTEXT=OFF
  -DENABLE_SOUND=OFF
  -DENABLE_POSTGRESQL=OFF
  -DENABLE_LEVELDB=OFF
  -DENABLE_REDIS=OFF
  -DENABLE_PROMETHEUS=OFF
  -DENABLE_SPATIAL=OFF
  -DENABLE_UPDATE_CHECKER=OFF
)
CMAKE_ARGS+=("${ZSTD_ARGS[@]}")
if [[ "${ENGINE_USE_CCACHE:-1}" == 1 ]] && command -v ccache >/dev/null 2>&1; then
  CMAKE_ARGS+=(
    -DCMAKE_C_COMPILER_LAUNCHER=ccache
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
  )
fi
cmake "${CMAKE_ARGS[@]}"
cmake --build "$BUILD"

ARTIFACT="$(find "$BUILD" -name "lib${LIBRARY}.so" -print -quit)"
test -n "$ARTIFACT"
mkdir -p "$OUTPUT"
install -m 0644 "$ARTIFACT" "$OUTPUT/lib${LIBRARY}.so"
install -m 0644 "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt"/*/sysroot/usr/lib/"$SYSROOT_TRIPLE"/libc++_shared.so "$OUTPUT/" 2>/dev/null || true
PAGE_ALIGNMENT_OK=1
while read -r ALIGNMENT; do
  if (( ALIGNMENT < 0x4000 )); then
    PAGE_ALIGNMENT_OK=0
  fi
done < <(readelf -lW "$OUTPUT/lib${LIBRARY}.so" | awk '$1 == "LOAD" { print $NF }')
if (( PAGE_ALIGNMENT_OK == 0 )); then
  echo "native library is not compatible with 16 kB page-size devices: $OUTPUT/lib${LIBRARY}.so" >&2
  exit 70
fi
sha256sum "$OUTPUT"/*.so > "$OUTPUT/SHA256SUMS"
echo "built $ABI $OUTPUT/lib${LIBRARY}.so"
