#!/usr/bin/env python3
"""Turn Winlator Mali community configs (Gunacharan's Winlator-Mali-Community-Configs) into
per-game presets for PanVK on a Mali-G615 MC2.

For each game the newest config from a Mali-G615 MC2 phone is used; when there is none, the newest
G615 MC6/MC5 config is used and scaled down for the 2-core GPU. Then the config is pointed at the
PanVK driver package and settings that only exist to work around the vendor (Arm) driver are
removed, because PanVK does those itself (BCn decode, the OpConstantComposite patch).

The community repository has no license file, so its data is not stored in this repository: run
this tool against a local checkout (CI does it at the commit pinned in sources.lock.json).

Usage:
  tools/winlator_presets.py --configs path/to/Winlator-Mali-Community-Configs \
      --driver-name Mesa-PanVK-G615-MC2-<version> --out dist/winlator-presets
"""
import argparse, collections, copy, json, ntpath, pathlib, re, sys

SMALL_MAX_PIXELS = 1280 * 720          # MC2 has a third of the MC6 shader cores
MC6_DOWNSCALE = {                      # resolution used by MC6 config -> suggestion for MC2
    "1920x1080": "1280x720", "1600x720": "1280x576", "1560x720": "1280x590",
    "1540x768": "1280x640", "1366x768": "1280x720", "1360x612": "1280x576",
}
# Env vars that only make sense for the Arm vendor driver behind the Vulkan wrapper.
DROP_ENV = {
    "WRAPPER_NO_PATCH_OPCONSTCOMP",  # vendor shader compiler bug workaround
    "BCN_TRANSCODE_TO_ASTC",         # PanVK decodes BCn itself
}
# graphicsDriverConfig keys reset for PanVK (it advertises textureCompressionBC and manages
# memory itself; the wrapper must not emulate or cap on top of it).
DRIVER_CFG_OVERRIDES = {"bcnEmulation": "none", "bcnEnabled": "0", "maxDeviceMemory": "0"}


def parse_kv(s, sep):
    out = collections.OrderedDict()
    for part in (s or "").split(sep):
        if "=" in part:
            k, v = part.split("=", 1)
            out[k] = v
    return out


def join_kv(d, sep):
    return sep.join(f"{k}={v}" for k, v in d.items())


def gpu_tier(cfg):
    gpu = cfg.get("meta", {}).get("device", {}).get("gpu", "")
    m = re.search(r"G615\s+MC(\d+)", gpu)
    return int(m.group(1)) if m else None


def area(res):
    m = re.fullmatch(r"(\d+)x(\d+)", res or "")
    return int(m.group(1)) * int(m.group(2)) if m else None


def scale_res(res):
    a = area(res)
    if a is None or a <= SMALL_MAX_PIXELS:
        return res
    return MC6_DOWNSCALE.get(res, "1280x720")


def convert(cfg, driver_name, source_rel, from_mc2):
    out = copy.deepcopy(cfg)
    notes = []
    c = out.setdefault("container", {})

    gdc = parse_kv(c.get("graphicsDriverConfig"), ";")
    gdc["version"] = driver_name
    gdc.update(DRIVER_CFG_OVERRIDES)
    c["graphicsDriverConfig"] = join_kv(gdc, ";")
    if not str(c.get("graphicsDriver", "")).startswith("wrapper"):
        c["graphicsDriver"] = "wrapper"
        notes.append("graphics driver set to the Vulkan wrapper so the PanVK package is used")

    env = [e for e in (c.get("envVars") or "").split() if e.split("=", 1)[0] not in DROP_ENV]
    dropped = sorted({e.split("=", 1)[0] for e in (c.get("envVars") or "").split()} & DROP_ENV)
    if dropped:
        notes.append("removed vendor-driver workarounds: " + ", ".join(dropped))
    c["envVars"] = " ".join(env)

    if not from_mc2:
        old = c.get("screenSize")
        new = scale_res(old)
        if new != old:
            c["screenSize"] = new
            notes.append(f"resolution {old} -> {new} for the 2-core GPU")
        notes.append("based on a Mali-G615 MC6/MC5 config (6 shader cores vs 2): expect lower frame rates")

    # The shortcut copy carries the same fields as strings; keep it consistent.
    sc = out.get("shortcut", {}).get("extraData")
    if isinstance(sc, dict):
        if "graphicsDriverConfig" in sc:
            sgdc = parse_kv(sc["graphicsDriverConfig"], ";")
            sgdc["version"] = driver_name
            sgdc.update(DRIVER_CFG_OVERRIDES)
            sc["graphicsDriverConfig"] = join_kv(sgdc, ";")
        if not from_mc2 and "screenSize" in sc:
            sc["screenSize"] = c.get("screenSize", sc["screenSize"])

    meta = out.setdefault("meta", {})
    meta["config_title"] = f"{meta.get('config_title') or meta.get('game_name')} [PanVK G615 MC2]"
    meta["notes"] = ("Converted for PanVK on Mali-G615 MC2 by tools/winlator_presets.py from "
                     f"{source_rel}. " + "; ".join(notes) +
                     (f". Original notes: {cfg['meta']['notes']}" if cfg.get("meta", {}).get("notes") else ""))
    meta.setdefault("device", {})["gpu"] = "Mali-G615 MC2"
    return out, notes


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--configs", required=True, help="checkout of Winlator-Mali-Community-Configs")
    ap.add_argument("--driver-name", required=True, help="meta.json name of the PanVK package")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    root = pathlib.Path(a.configs)
    best = {}
    for f in sorted((root / "configs").glob("*/*.json")):
        try:
            cfg = json.loads(f.read_text())
        except (ValueError, UnicodeDecodeError):
            continue
        tier = gpu_tier(cfg)
        if tier is None:
            continue
        game = f.parent.name
        ts = cfg.get("meta", {}).get("timestamp") or 0
        key = (tier == 2, ts)                       # prefer MC2, then newest
        if game not in best or key > best[game][0]:
            best[game] = (key, f, cfg)

    out = pathlib.Path(a.out)
    out.mkdir(parents=True, exist_ok=True)
    index = []
    for game, (key, f, cfg) in sorted(best.items()):
        from_mc2 = key[0]
        rel = f.relative_to(root).as_posix()
        conv, notes = convert(cfg, a.driver_name, rel, from_mc2)
        (out / f"{game}.json").write_text(json.dumps(conv, indent=2, ensure_ascii=False) + "\n")
        c = conv["container"]
        dxc = parse_kv(c.get("dxwrapperConfig"), ",")
        index.append({
            "id": game,
            "name": cfg["meta"].get("game_name"),
            "exe": ntpath.basename((cfg.get("shortcut") or {}).get("path") or ""),
            "source": rel,
            "sourceGpu": cfg["meta"]["device"].get("gpu"),
            "fromMc2": from_mc2,
            "dxvk": dxc.get("version"), "vkd3d": dxc.get("vkd3dVersion"),
            "emulator": c.get("emulator"), "screenSize": c.get("screenSize"),
            "notes": notes,
        })
    (out / "index.json").write_text(json.dumps(index, indent=2, ensure_ascii=False) + "\n")
    n2 = sum(1 for i in index if i["fromMc2"])
    print(f"OK {len(index)} presets ({n2} from MC2 configs, {len(index) - n2} scaled from MC6/MC5) -> {out}")


if __name__ == "__main__":
    sys.exit(main())
