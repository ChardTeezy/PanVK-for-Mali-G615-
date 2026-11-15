#!/bin/sh
# build-host-tools.sh - native Mesa codegen tools (mesa_clc, vtn_bindgen2, panfrost_compile)
# needed by the Android cross build. Needs LLVM/Clang 18 with libclc and SPIRV-LLVM-Translator.
# Usage: scripts/build-host-tools.sh   (output: build/host-tools/bin)
set -eu
. "$(dirname "$0")/common.sh"
OUT="${HOST_TOOLS_DIR:-$ROOT/build/host-tools}"
[ -f "$OUT/build.ninja" ] || meson setup "$OUT" "$MESA_DIR" -Dbuildtype=release \
  -Dgallium-drivers= -Dvulkan-drivers=panfrost -Dplatforms= -Dglx=disabled -Degl=disabled \
  -Dgbm=disabled -Dopengl=false -Dgles1=disabled -Dgles2=disabled -Dmesa-clc=enabled \
  -Dinstall-mesa-clc=true -Dprecomp-compiler=enabled -Dinstall-precomp-compiler=true \
  -Dllvm=enabled -Dzstd=disabled
ninja -j"${JOBS:-$(nproc)}" -C "$OUT" src/compiler/clc/mesa_clc src/compiler/spirv/vtn_bindgen2 src/panfrost/clc/panfrost_compile
mkdir -p "$OUT/bin"
for p in src/compiler/clc/mesa_clc src/compiler/spirv/vtn_bindgen2 src/panfrost/clc/panfrost_compile; do
  ln -sf "../$p" "$OUT/bin/$(basename "$p")"
done
echo "OK host tools: $OUT/bin"
