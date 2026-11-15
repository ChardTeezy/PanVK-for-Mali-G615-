# Notice

- **Mesa** (https://gitlab.freedesktop.org/mesa/mesa): the driver source. PanVK and the Mesa
  utility code are MIT licensed. The files in `patches/` and `overlay/` modify Mesa and are
  offered under the same MIT terms.
- **panvk-kbase-android** (https://github.com/zenithblue-oss/panvk-kbase-android): the base
  patch stack (mali_kbase backend, v11 CSF support and the rest). It is fetched at build time at
  the commit pinned in `sources.lock.json`, not copied here. Its patches keep their authors and
  licenses; see that project's `LICENSES/` and `NOTICE.md`. The Unity video memory finding used
  in `compat/game-profiles.json` comes from its `worklogs/apps/panplay-games.md`.
- **Winlator-Mali-Community-Configs** by Gunacharan
  (https://github.com/GunaCharanTeja/Winlator-Mali-Community-Configs): community game configs.
  This repository uses them as a reference (statistics in `docs/WINLATOR.md`, game `.exe` names)
  and `tools/winlator_presets.py` reads them from a local checkout. The configs themselves are not
  redistributed, because that repository has no license file.
