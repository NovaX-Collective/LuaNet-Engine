# LuaNet Engine

LuaNet Engine contains the open-source native engine integration used by the
proprietary LuaNet Android app. It turns pinned Luanti dedicated-server releases
into ARM64 Android shared libraries and exposes the small JNI bridge used to
start, stop and manage those servers.

The LuaNet Android application, NovaX control plane, tunnel infrastructure and
website are not part of this repository.

## Included

- Exact upstream tag and commit pins for every supported Luanti engine.
- LGPL-licensed LuaNet native bridge and compatibility shims.
- Reproducible source transformations and Android build scripts.
- Pinned native dependency revisions and archive checksum.
- Tooling for producing complete corresponding-source archives.

## Supported engines

The current catalog contains Luanti/Minetest `5.0.1` through `5.16.1`. The
latest engine is delivered in the LuaNet base app; older engines may be
delivered using Google Play Feature Delivery.

Validate the catalog:

```bash
python3 scripts/validate-catalog.py
```

Build an engine with Android NDK available as `ANDROID_NDK_HOME`:

```bash
scripts/build-version.sh 5.16.1
```

Create corresponding-source archives for one engine or the entire catalog:

```bash
scripts/create-source-bundle.sh 5.16.1
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
