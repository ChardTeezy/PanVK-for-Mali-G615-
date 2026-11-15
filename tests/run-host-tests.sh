#!/bin/sh
# run-host-tests.sh - host (x86_64) tests of the MC2 driver changes against the prepared tree:
#  1. driconf profile matching through Mesa's static driconf (the code path Android uses);
#  2. panvk_apply_env_defaults() parsing and precedence.
# Needs: scripts/prepare-tree.sh done, host tools built (mesa_clc etc. on PATH or in build/host-tools).
set -eu
. "$(dirname "$0")/../scripts/common.sh"
B="$ROOT/build/host-static-driconf"; T="$ROOT/build/host-tests"; H="$ROOT/tests/host"
export PATH="${HOST_TOOLS_DIR:-$ROOT/build/host-tools}/bin:$PATH"
[ -f "$B/build.ninja" ] || meson setup "$B" "$MESA_DIR" -Dbuildtype=debug -Dxmlconfig=disabled \
  -Dgallium-drivers= -Dvulkan-drivers=panfrost -Dplatforms= -Dglx=disabled -Degl=disabled \
  -Dgbm=disabled -Dopengl=false -Dgles1=disabled -Dgles2=disabled -Dmesa-clc=system \
  -Dprecomp-compiler=system -Dllvm=disabled -Dzstd=disabled -Dvalgrind=disabled >/dev/null
ninja -C "$B" src/panfrost/vulkan/panvk_drirc.c src/panfrost/vulkan/panvk_drirc.h \
  src/util/libxmlconfig.a src/util/libmesa_util.a src/util/blake3/libblake3.a src/c11/impl/libmesa_util_c11.a >/dev/null
FLAGS="$(python3 -I -c "
import json, shlex
d = json.load(open('$B/compile_commands.json'))
c = next(e for e in d if e['file'].endswith('util/os_misc.c'))
print(' '.join(shlex.quote(x) for x in shlex.split(c['command']) if x.startswith(('-D', '-std'))))")"
INC="-I$MESA_DIR/src -I$MESA_DIR/include -I$B/src -I$MESA_DIR/src/util -I$B/src/util -I$B/src/panfrost/vulkan -I$T"
LIBS="$B/src/util/libxmlconfig.a $B/src/util/libmesa_util.a $B/src/util/blake3/libblake3.a $B/src/c11/impl/libmesa_util_c11.a -lm -lpthread -ldl -lz"
mkdir -p "$T"
sed -n '/^panvk_env_default_key_allowed/,/^panvk_init_dri_options/p' "$MESA_DIR/src/panfrost/vulkan/panvk_instance.c" \
  | sed '1i static bool' | head -n -3 > "$T/fn.inc"
grep -q '^panvk_apply_env_defaults' "$T/fn.inc" || die "could not extract panvk_apply_env_defaults"
eval cc $FLAGS -o "$T/driconf_match" "$H/driconf_match.c" "$B/src/panfrost/vulkan/panvk_drirc.c" $INC $LIBS
eval cc $FLAGS -o "$T/env_defaults" "$H/env_defaults.c" $INC $LIBS

echo "== driconf profile matching"
"$T/driconf_match" \
  "Hollow Knight Silksong.exe" DXVK  "PANVK_HEAP_MAX_MB=2048" \
  "HOLLOW KNIGHT SILKSONG.EXE" vkd3d "PANVK_HEAP_MAX_MB=2048" \
  "cuphead.exe"                DXVK  "PANVK_HEAP_MAX_MB=2048" \
  "disco.exe"                  DXVK  "PANVK_HEAP_MAX_MB=2048" \
  "Cuphead_exe"                DXVK  "" \
  "Cuphead.exe.bak"            DXVK  "" \
  "GTA5.exe"                   DXVK  "" \
  "x"                          ANGLE ""
echo "== panvk_apply_env_defaults"
env -u PANVK_HEAP_MAX_MB -u MESA_X -u PANVK_EMPTY "$T/env_defaults"
echo "OK host tests"
