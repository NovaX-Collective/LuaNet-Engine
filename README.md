# LuaNet Engine

LuaNet Engine contains the open-source native engine integration used by the
proprietary LuaNet Android app. It turns pinned Luanti dedicated-server releases
into ARM64, ARMv7 and x86_64 Android shared libraries and exposes the small JNI
bridge used to start, stop and manage those servers.

The LuaNet Android application, NovaX control plane, tunnel infrastructure and
website are not part of this repository.

## Included

- Exact upstream tag and commit pins for every supported Luanti engine.
- LGPL-licensed LuaNet native bridge and compatibility shims.
- Reproducible source transformations and Android build scripts.
- A three-ABI build matrix for modern phones, older 32-bit ARM devices and
  x86_64 Android environments.
- 16 kB ELF page alignment for current and future 64-bit Android devices.
- Pinned native dependency revisions and archive checksum.
- Tooling for producing complete corresponding-source archives.

## Supported engines

The current catalog contains Luanti/Minetest `5.0.1` through `5.17.0`. Every
version is delivered as an independent on-demand Play feature, so installing
LuaNet does not download engine versions that a user never selects.

Validate the catalog:

```bash
python3 scripts/validate-catalog.py
```

Build an engine with Android NDK available as `ANDROID_NDK_HOME`:

```bash
scripts/build-version.sh 5.17.0 arm64-v8a
scripts/build-version.sh 5.17.0 armeabi-v7a
scripts/build-version.sh 5.17.0 x86_64
```

After validating one version and ABI, `scripts/build-all.sh` builds the complete
catalog and `scripts/sync-android-artifacts.sh` stages it for Android packaging.
The manual GitHub Actions workflow performs the same complete build across all
three ABIs. Artifacts are disabled by default to avoid consuming Actions
storage; they can be enabled for a run and expire after one day.

Create corresponding-source archives for one engine or the entire catalog:

```bash
scripts/create-source-bundle.sh 5.17.0
scripts/create-source-bundle.sh
```

Published LuaNet releases attach the corresponding-source archives to a tagged
GitHub release in this repository.

## Licensing

The LuaNet bridge and engine modifications are licensed under
LGPL-2.1-or-later. Luanti and bundled third-party files retain their applicable
upstream licenses and copyright notices. See [LICENSE](LICENSE),
[NOTICE.md](NOTICE.md), and [LICENSES](LICENSES).

LuaNet is not affiliated with or endorsed by the Luanti project.

Project information is available at [luanet.net](https://luanet.net).
