#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_ROOT="${OUTPUT_ROOT:-$ROOT/release-sources}"
CACHE="$ROOT/.cache/luanti-source.git"

if [[ $# -eq 0 ]]; then
  mapfile -t VERSIONS < <(python3 - "$ROOT/catalog.json" <<'PY'
import json, sys
for item in json.load(open(sys.argv[1]))["engines"]:
    print(item["version"])
PY
  )
else
  VERSIONS=("$@")
fi

mkdir -p "$OUTPUT_ROOT"
if [[ ! -d "$CACHE" ]]; then
  git init --bare "$CACHE"
  git -C "$CACHE" remote add origin https://github.com/luanti-org/luanti.git
fi

for version in "${VERSIONS[@]}"; do
  mapfile -t META < <(python3 - "$ROOT/catalog.json" "$version" <<'PY'
import json, sys
item = next((x for x in json.load(open(sys.argv[1]))["engines"] if x["version"] == sys.argv[2]), None)
if item is None:
    raise SystemExit(f"unsupported engine {sys.argv[2]}")
print(item["tag"])
print(item["commit"])
print(item["library"])
PY
  )
  tag="${META[0]}"
  commit="${META[1]}"
  library="${META[2]}"

  git -C "$CACHE" fetch --force --depth 1 origin "refs/tags/$tag:refs/tags/$tag"
  actual="$(git -C "$CACHE" rev-parse "refs/tags/$tag^{}")"
  if [[ "$actual" != "$commit" ]]; then
    echo "source verification failed for $version: expected $commit, got $actual" >&2
    exit 65
  fi

  work="$(mktemp -d)"
  source="$work/luanet-engine-$version-source"
  git clone --quiet --no-checkout "$CACHE" "$source"
  git -C "$source" checkout -q --detach "$commit"
  git -C "$source" submodule update --init --recursive --depth 1

  mkdir -p "$source/luanet"
  cp -a "$ROOT/bridge" "$source/luanet/bridge"
  cp "$ROOT/catalog.json" "$ROOT/dependencies.json" "$source/luanet/"
  cp -a "$ROOT/scripts" "$source/luanet/build-scripts"
  rm -rf "$source/luanet/build-scripts/__pycache__"

  python3 "$ROOT/scripts/prepare-source.py" "$source" \
    --bridge "$source/luanet/bridge/src/luanet_engine.cpp" \
    --library "$library"
  python3 - "$source" <<'PY'
import sys
from pathlib import Path
root = Path(sys.argv[1])
cmake = root / "src" / "CMakeLists.txt"
text = cmake.read_text()
text = text.replace(str(root / "luanet" / "bridge"), "${PROJECT_SOURCE_DIR}/luanet/bridge")
cmake.write_text(text)
PY

  cat > "$source/LUANET-SOURCE.txt" <<EOF
LuaNet engine corresponding source
Engine version: $version
Upstream tag: $tag
Upstream commit: $commit
Output library: lib$library.so

This archive contains the complete Luanti source checkout, initialized
submodules, LuaNet native bridge, applied source transformations, catalog,
dependency pins, and build scripts used for the LuaNet Android engine.

LuaNet-Engine: https://github.com/Just-Nova23/LuaNet-Engine
EOF

  find "$source" -name .git -type d -prune -exec rm -rf {} \;
  find "$source" -name .git -type f -delete
  archive="$OUTPUT_ROOT/luanet-engine-$version-source.tar.gz"
  tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    -C "$work" -czf "$archive" "$(basename "$source")"
  (
    cd "$OUTPUT_ROOT"
    sha256sum "$(basename "$archive")" > "$(basename "$archive").sha256"
  )
  rm -rf "$work"
  echo "created $archive"
done
