# PanVK for Mali-G615 MC2

An open Mesa **PanVK** Vulkan driver package for **Arm Mali-G615 MC2** phones and tablets (MediaTek Dimensity 7300 / 7400 class), built for **Winlator** and other AdrenoTools frontends. It runs Windows PC games through DXVK (D3D8 to D3D11) and vkd3d-proton (D3D12).

This repository is a small, reviewable layer on top of two projects:

| Project | What it provides |
|---|---|
| [zenithblue-oss/panvk-kbase-android](https://github.com/zenithblue-oss/panvk-kbase-android) | The driver: Mesa PanVK running on Android's stock `mali_kbase` kernel driver (`/dev/mali0`), with about 400 patches for v11 (G615/G715) CSF, GPU geometry and tessellation, BC1 to BC7 decode, X11 present for Winlator, and more. Pinned by commit; fetched at build time. |
| [GunaCharanTeja/Winlator-Mali-Community-Configs](https://github.com/GunaCharanTeja/Winlator-Mali-Community-Configs) (Gunacharan) | Community Winlator Mali configs for 400+ games, 151 of them from Mali-G615 phones (43 from MC2). Used as the reference for what MC2 phones actually need, and converted into per-game PanVK presets at build time. |

## What this layer adds for the G615 MC2

The base driver already supports the G615 (it is tuned and tested on a G615 **MC6**, Poco X6 Pro). MC2 parts have a third of the shader cores and usually ship with 6 to 8 GB of RAM. The community configs show what MC2 users change by hand: 42 of 43 use 2 GB of video memory, many cap the device memory, and the resolution is 1280x720 or lower. This layer moves that into the driver and the presets.

| Change | Where | What it does |
|---|---|---|
| Small-G615 heap sizing | [`patches/0002`](patches/0002-small-g615-heap-sizing.patch) | On a G615 with 3 or fewer cores, the Vulkan heap (what DXGI reports as video memory) is 40 % of RAM up to 6 GB, 45 % up to 8 GB, 55 % up to 12 GB, instead of Mesa's 75 %. On an 8 GB phone that is about 3.3 GiB instead of 5.6 GiB, so DXVK, vkd3d-proton, Unity and Unreal do not size their pools past what Android leaves free. |
| `PANVK_HEAP_MAX_MB` | [`patches/0002`](patches/0002-small-g615-heap-sizing.patch) | Caps the reported video memory, per game or by hand. |
| Per-game profiles | [`patches/0001`](patches/0001-pan-env-defaults-driconf.patch), [`compat/game-profiles.json`](compat/game-profiles.json) | A new driconf option, `pan_env_defaults`, applies PANVK knobs per game. DXVK and vkd3d-proton report the game's `.exe` name, so profiles match on it. Shipped profile: 14 Unity games get a 2 GiB video memory cap, the fix the base project found for Unity's "Crash!!!" on Hollow Knight: Silksong. |
| Winlator presets | [`tools/winlator_presets.py`](tools/winlator_presets.py) | Turns Gunacharan's configs into one preset per game (118 games) for this driver: picks the newest MC2 config, or scales a MC6 config down to 1280x720 or less; selects this driver package; turns off the wrapper's BCn emulation and memory cap (PanVK does both itself); and drops vendor-driver-only workarounds such as `WRAPPER_NO_PATCH_OPCONSTCOMP`. |

Your own environment variables always win over the profiles and defaults.

## Install

1. Download `Mesa-PanVK-G615-MC2-<version>.zip` from the [releases](../../releases) page, or from the CI artifact of the latest build.
2. In Winlator: **Settings > Graphics drivers > Install** and pick the zip.
3. In the container: **Graphics Driver = Wrapper**, **Graphics Driver Version = Mesa-PanVK-G615-MC2-<version>**, BCn emulation **off**.
4. Optional: generate per-game presets on a PC with `tools/winlator_presets.py` (see [`docs/WINLATOR.md`](docs/WINLATOR.md#per-game-presets)) and import the one for your game. They are not shipped in the release because the community configs repository has no license yet.

More detail and troubleshooting: [`docs/WINLATOR.md`](docs/WINLATOR.md).

### Knobs

Set these in container > Environment variables.

| Variable | Effect |
|---|---|
| `PANVK_G615_SMALL=0` | Turn off the MC2 heap sizing. `=1` turns it on for other G615s (for example an 8 GB MC6). |
| `heap_memory_percent=0.6` | Report a different share of RAM as video memory (0 to 1). |
| `PANVK_HEAP_MAX_MB=2048` | Cap the reported video memory, in MiB. |
| `PANVK_DEBUG=...`, `PANVK_BC_*`, `PANVK_KBASE_*` | Base driver knobs. See the base project's [docs](https://github.com/zenithblue-oss/panvk-kbase-android/tree/main/docs). |

## Build

The build runs on Linux x86_64 with LLVM/Clang 18, libclc, SPIRV-LLVM-Translator and the Android NDK. CI does the full build on every push: [`.github/workflows/build.yml`](.github/workflows/build.yml) lists the packages.

```bash
scripts/fetch-sources.sh
```

```bash
scripts/prepare-tree.sh
```

```bash
scripts/build-host-tools.sh
```

```bash
scripts/build-android.sh --ndk "$ANDROID_NDK_ROOT"
```

```bash
scripts/package.sh --version 0.1.0 --configs path/to/Winlator-Mali-Community-Configs
```

- `fetch-sources.sh` fetches the pinned base and Mesa commits from [`sources.lock.json`](sources.lock.json).
- `prepare-tree.sh` applies the base stack in the base project's order, then `patches/*.patch` and the generated driconf overlay. Every patch must apply exactly, with no fuzz.
- `tests/run-host-tests.sh` checks, on the build machine, that Mesa's static driconf (the path Android uses) gives each `.exe` name the right profile, and that `pan_env_defaults` parsing keeps user values. `tests/test_tools.py` covers the two Python tools.
- After editing `compat/game-profiles.json`, run `tools/gen_driconf.py --base-conf work/mesa/src/panfrost/vulkan/00-panvk-defaults.conf`. CI fails if the overlay is stale.

## Status and limits

- **Built and host-tested, not yet run on an MC2 device.** The patches apply cleanly on the pinned base, the driver cross-compiles for arm64 Android, and the profile matching and knob handling pass host tests. The base driver is device-tested on G615 MC6; the MC2 changes have not been run on MC2 hardware yet. Reports from MC2 owners are what moves this forward: see [`docs/WINLATOR.md`](docs/WINLATOR.md#reporting-a-game).
- This is not a fix for every game. It inherits the base driver's limits: no D3D12 feature level 12_x (sparse binding is not possible on kbase), Fallout 4 has a black face on DXVK, and some games need game-side settings (for example MSAA off in Dark Souls).
- Per-game profiles are added only with evidence: a log, a device run, or a base-project finding. Each group in `compat/game-profiles.json` records its evidence.

## License

Scripts and tools in this repository: MIT ([`LICENSE`](LICENSE)). Mesa and the base patch stack keep their own licenses (MIT for Mesa's PanVK; see the base project's `LICENSES/`). Community configs are not redistributed here; see [`NOTICE.md`](NOTICE.md).
