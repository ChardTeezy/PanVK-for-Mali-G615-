# PanVK G615 MC2 in Winlator

## Setup

1. Install the driver zip: **Settings > Graphics drivers (AdrenoTools) > Install**.
2. Container settings:

   | Setting | Value | Why |
   |---|---|---|
   | Graphics Driver | Wrapper | The wrapper owns the Android/X11 present path; PanVK renders. |
   | Graphics Driver Version | `Mesa-PanVK-G615-MC2-<version>` | Loads this driver instead of the Arm driver. |
   | BCn emulation | Off (`bcnEmulation=none`) | PanVK decodes BC1 to BC7 on the GPU itself. Doing it twice wastes memory. |
   | Max device memory | 0 (off) | PanVK sizes the heap for MC2 phones itself. |
   | DXVK | Same version the community config for your game uses | DXVK 1.10.x/2.x for D3D9 to D3D11 titles. |
   | VKD3D | 2.x for D3D12 titles | Feature level 11_x only; 12_x is not available on kbase. |
   | Resolution | 1280x720 or lower | MC2 has 2 shader cores. |

3. Leave out these environment variables if a config you copied has them. They work around the Arm driver, not PanVK:
   - `WRAPPER_NO_PATCH_OPCONSTCOMP`
   - `BCN_TRANSCODE_TO_ASTC`

## Is PanVK running?

- DXVK HUD with `devinfo` shows the driver as PanVK and the device as `Mali-G615 MC2`. A `gpuName=` spoof in the wrapper settings can change the device name shown.
- `logcat | grep panvk` shows `small G615 tuning on (2 cores)` and the heap size picked, and `app profile for "<game>.exe"` when a game profile matched.

## What the community configs say about MC2 phones

From the Winlator Mali community configs at the commit pinned in `sources.lock.json`: 151 configs from Mali-G615 phones; 43 from MC2, 107 from MC6, 1 from MC5.

| | MC2 (43 configs) | MC6 (107 configs) |
|---|---|---|
| RAM | 8 GB: 26, 6 GB: 11, 12 GB: 6 | 12 GB: 57, 8 GB: 50 |
| Video memory | 2048 MB in 42 | 2048 MB in 106 |
| Device memory capped | 12 of 43 | 14 of 107 |
| Resolution | 1280x720: 21; 960x544 or lower: 15 | 1280x720: 71; 960x544 or lower: 31 |
| Present mode | mailbox: 40 | mailbox: 107 |
| Emulator | FEXCore: 36, Box64: 7 | FEXCore: 85, Box64: 22 |

All 151 use DXVK+VKD3D and Vulkan 1.3 in the wrapper, and 150 have the wrapper's BCn emulation on (`auto` or `full`), because the Arm driver has no BCn support. BCn emulation in the wrapper is not needed with PanVK.

## Per-game presets

`tools/winlator_presets.py` turns the community configs into one preset per game for this driver. Run it on a PC, then copy the JSON for your game to the phone and import it in Winlator Mali.

```bash
git clone https://github.com/GunaCharanTeja/Winlator-Mali-Community-Configs
```

```bash
python3 tools/winlator_presets.py --configs Winlator-Mali-Community-Configs --driver-name Mesa-PanVK-G615-MC2-<version> --out presets
```

For each game the tool:
- takes the newest config from an MC2 phone, or, if there is none, the newest MC6/MC5 config with the resolution capped at 1280x720 (wide screens map to the same height, e.g. 1600x720 to 1280x576);
- sets Graphics Driver Version to the PanVK package, turns off the wrapper's BCn emulation and device memory cap;
- removes the vendor-driver workarounds listed above;
- keeps everything else (DXVK/VKD3D versions, FEX/Box64 presets, CPU cores, Wine version, audio) and records what it changed in the preset's `notes`.

`presets/index.json` lists every game with its source config, DXVK/VKD3D version and the changes.

## Per-game driver profiles

Profiles live in `compat/game-profiles.json`, grouped by fix. A profile sets driconf options for one `.exe` name; the name match is case-insensitive. Current groups:

| Group | Games | Setting | Evidence |
|---|---|---|---|
| `unity-vram-cap` | 14 Unity games (Silksong, Hollow Knight, Cuphead, Ori DE, MiSide, Neon White, Dave the Diver, Firewatch, Blasphemous 2, Megabonk, Disco Elysium, Fears to Fathom, Story of Seasons FoMT, Cat Quest) | `PANVK_HEAP_MAX_MB=2048` | Base project found Unity's "Crash!!!" on Silksong comes from over-sized DXGI video memory, fixed by a 2048 MiB cap. |

To add a profile: add the game to a group (or a new group with an `evidence` line), run `tools/gen_driconf.py`, rebuild. Options a profile can set: `pan_env_defaults` (PANVK_*/MESA_* knobs, `;` separated), `heap_memory_percent`, and the Mesa WSI options listed in `tools/gen_driconf.py`.

## Known problems

Inherited from the base driver:
- D3D12 feature level 12_x is reported unsupported; games that require it will not start. 11_x games run.
- Fallout 4 on DXVK: black faces.
- Dark Souls: Prepare to Die: black 3D unless Blur and Antialiasing are off in `DarkSouls.ini`.
- Burnout Paradise: broken world from Proton's bundled d3dcompiler; needs Wine's `d3dcompiler_43` and `wined3d` as native.
- Games with DRM that executes encrypted code (SecuROM 7, e.g. some NFS Undercover installs) do not run under FEX.

## Reporting a game

Open an issue with:
- phone model, SoC, RAM, Android version;
- the driver zip name and the line `panvk: small G615 tuning ...` from logcat;
- game, `.exe` name, DXVK/VKD3D version, FEX/Box64 preset, resolution;
- what happened (crash, black screen, glitches, FPS), and the DXVK logs (`<game>_d3d11.log`, `<game>_dxgi.log`);
- `logcat -d | grep -iE 'vulkan|panvk|mesa'`.
