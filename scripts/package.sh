#!/bin/sh
# package.sh - build the Winlator / AdrenoTools driver zip (and the per-game presets zip).
# Usage: scripts/package.sh --version 1.0.0 [--so dist/libvulkan_panfrost.so] [--configs DIR]
#   --configs: checkout of Winlator-Mali-Community-Configs; adds dist/*-winlator-presets.zip
set -eu
. "$(dirname "$0")/common.sh"
VER=""; SO="$ROOT/dist/libvulkan_panfrost.so"; CONFIGS=""
while [ $# -gt 0 ]; do case "$1" in
  --version) VER="$2"; shift 2;; --so) SO="$2"; shift 2;; --configs) CONFIGS="$2"; shift 2;;
  *) die "unknown arg $1";; esac; done
[ -n "$VER" ] || die "--version required"
[ -f "$SO" ] || die "$SO not found (run scripts/build-android.sh)"
NAME="Mesa-PanVK-G615-MC2-$VER"
OUT="$ROOT/dist"; mkdir -p "$OUT"
python3 - "$SO" "$VER" "$NAME" "$OUT" "$(lock mesa.commit)" "$(lock base.commit)" <<'PY'
import hashlib, json, sys, zipfile, pathlib
so, ver, name, out, mesa, base = sys.argv[1:]
data = pathlib.Path(so).read_bytes()
sha = hashlib.sha256(data).hexdigest()
meta = {
    "schemaVersion": 1,
    "name": name,
    "description": ("Mesa PanVK (mali_kbase) for Mali-G615 MC2 with small-GPU heap sizing and per-game "
                    f"profiles. Base panvk-kbase-android {base[:10]}, Mesa {mesa[:10]}."),
    "author": "PanVK-for-Mali-G615",
    "packageVersion": ver,
    "vendor": "Mesa",
    "driverVersion": f"Mesa 26.3.0-devel PanVK G615-MC2 {ver}",
    "minApi": 29,
    "libraryName": "libvulkan_panfrost.so",
}
readme = f"""{name}

Install (Winlator / Winlator Mali / Ludashi / Bannerlator / any AdrenoTools frontend):
  Settings > Graphics drivers (AdrenoTools) > Install > pick this zip.
  In the container: Graphics Driver = Wrapper, Graphics Driver Version = {name}.
  Turn the wrapper's BCn emulation off (PanVK decodes BC1-BC7 on the GPU itself).

Check it loaded: DXVK HUD "devinfo" shows the PanVK driver (a gpuName spoof in the
wrapper settings changes the device name shown); logcat shows
"panvk: Mali-G615 MC2: small G615 tuning on (2 cores)".

Knobs (container > Environment variables):
  PANVK_G615_SMALL=0       disable the MC2 heap sizing
  heap_memory_percent=0.6  report 60 % of RAM as video memory instead
  PANVK_HEAP_MAX_MB=2048   cap reported video memory (MiB)

libvulkan_panfrost.so sha256 {sha}
"""
files = {
    "libvulkan_panfrost.so": data,
    "meta.json": (json.dumps(meta, indent=2) + "\n").encode(),
    "README.txt": readme.encode(),
    "SHA256SUMS.txt": f"{sha}  libvulkan_panfrost.so\n".encode(),
}
zp = pathlib.Path(out) / f"{name}.zip"
with zipfile.ZipFile(zp, "w", zipfile.ZIP_DEFLATED) as z:
    for n in sorted(files):
        zi = zipfile.ZipInfo(n, (2026, 1, 1, 0, 0, 0))
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.external_attr = 0o644 << 16
        z.writestr(zi, files[n])
print(f"OK {zp}")
PY
if [ -n "$CONFIGS" ]; then
  P="$WORK/winlator-presets"; rm -rf "$P"
  python3 -I "$ROOT/tools/winlator_presets.py" --configs "$CONFIGS" --driver-name "$NAME" --out "$P"
  (cd "$P" && rm -f "$OUT/$NAME-winlator-presets.zip" && zip -qr "$OUT/$NAME-winlator-presets.zip" .)
  echo "OK $OUT/$NAME-winlator-presets.zip"
fi
