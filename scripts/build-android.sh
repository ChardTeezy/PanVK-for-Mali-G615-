#!/bin/sh
# build-android.sh - cross-build libvulkan_panfrost.so (arm64-v8a, Bionic) from work/mesa.
# Usage: scripts/build-android.sh [--api 29] [--ndk DIR]
#   API 29 keeps the ICD loadable on Android 10+. NDK defaults to $ANDROID_NDK_ROOT /
#   $ANDROID_NDK_LATEST_HOME (GitHub runners).
set -eu
. "$(dirname "$0")/common.sh"
API=29; NDK="${ANDROID_NDK_ROOT:-${ANDROID_NDK_LATEST_HOME:-}}"
while [ $# -gt 0 ]; do case "$1" in
  --api) API="$2"; shift 2;; --ndk) NDK="$2"; shift 2;; *) die "unknown arg $1";; esac; done
[ -n "$NDK" ] || die "set ANDROID_NDK_ROOT or pass --ndk"
NDK_BIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
[ -x "$NDK_BIN/aarch64-linux-android$API-clang" ] || die "no aarch64-linux-android$API-clang in $NDK_BIN"
HOST_BIN="${HOST_TOOLS_DIR:-$ROOT/build/host-tools}/bin"
[ -x "$HOST_BIN/mesa_clc" ] || die "run scripts/build-host-tools.sh first"
export PATH="$HOST_BIN:$NDK_BIN:$PATH"
BUILD="$ROOT/build"; mkdir -p "$BUILD"
DEPS="$WORK/android-deps"; X11="$WORK/android-deps-x11"

# 1. libdrm: static, headers + pkg-config only (kbase does not use DRM; Mesa util includes xf86drm.h).
if [ ! -f "$DEPS/lib/pkgconfig/libdrm.pc" ]; then
  [ -d "$WORK/libdrm/.git" ] || git clone -q --depth 1 -b "$(lock libdrm)" https://gitlab.freedesktop.org/mesa/drm.git "$WORK/libdrm"
  sed "s/android29/android$API/g" "$ROOT/meson/android-aarch64.ini" > "$BUILD/libdrm.cross.ini"
  PKG_CONFIG_LIBDIR=/nonexistent meson setup --wipe "$BUILD/libdrm" "$WORK/libdrm" --cross-file "$BUILD/libdrm.cross.ini" \
    --prefix="$DEPS" --libdir=lib -Dbuildtype=release -Ddefault_library=static \
    -Dintel=disabled -Dradeon=disabled -Damdgpu=disabled -Dnouveau=disabled -Dvmwgfx=disabled \
    -Domap=disabled -Dexynos=disabled -Dfreedreno=disabled -Dtegra=disabled -Dvc4=disabled \
    -Detnaviv=disabled -Dcairo-tests=disabled -Dman-pages=disabled -Dvalgrind=disabled \
    -Dtests=false -Dudev=false >"$BUILD/libdrm.log" 2>&1 || { tail -n 20 "$BUILD/libdrm.log"; die "libdrm setup"; }
  ninja -C "$BUILD/libdrm" install >>"$BUILD/libdrm.log" 2>&1 || { tail -n 20 "$BUILD/libdrm.log"; die "libdrm build"; }
  printf 'Name: zlib\nDescription: zlib from the NDK sysroot\nVersion: 1.3\nLibs: -lz\nCflags:\n' > "$DEPS/lib/pkgconfig/zlib.pc"
fi

# 2. X11/XCB headers only: the Android ICD dlopens libxcb at runtime (Winlator's X server path).
if [ ! -f "$X11/lib/pkgconfig/xcb.pc" ]; then
  INC=/usr/include
  [ -f "$INC/xcb/xcb.h" ] && [ -f "$INC/X11/Xlib-xcb.h" ] && [ -f "$INC/X11/xshmfence.h" ] || \
    die "need host libxcb, libx11 and libxshmfence headers (apt: libx11-xcb-dev libxcb-*-dev libxshmfence-dev)"
  mkdir -p "$X11/include" "$X11/lib/pkgconfig"; cp -r "$INC/xcb" "$INC/X11" "$X11/include/"
  for pc in xcb xcb-randr xcb-dri3 xcb-present xcb-shm xcb-sync xcb-xfixes x11-xcb xshmfence; do
    v="$(pkg-config --modversion "$pc" 2>/dev/null || echo 1.17.0)"
    printf 'prefix=%s\nincludedir=${prefix}/include\nName: %s\nDescription: headers only (runtime dlopen)\nVersion: %s\nCflags: -I${includedir}\nLibs:\n' \
      "$X11" "$pc" "$v" > "$X11/lib/pkgconfig/$pc.pc"
  done
fi

# 3. Mesa PanVK, kbase only.
CROSS="$BUILD/android.cross.ini"
sed "s/android29/android$API/g" "$ROOT/meson/android-aarch64.ini" > "$CROSS"
printf "pkg_config_libdir = ['%s', '%s']\n" "$DEPS/lib/pkgconfig" "$X11/lib/pkgconfig" >> "$CROSS"
BDIR="$BUILD/android"; LOG="$BUILD/android.log"
RECONF=""; [ -f "$BDIR/build.ninja" ] && RECONF="--reconfigure"
meson setup $RECONF "$BDIR" "$MESA_DIR" --cross-file "$CROSS" \
  -Dbuildtype=release -Dplatforms=android,x11 -Dandroid-stub=true -Dandroid-strict=false \
  -Dgallium-drivers= -Dvulkan-drivers=panfrost -Dpanfrost-kmds=kbase \
  -Dmesa-clc=system -Dprecomp-compiler=system -Dxlib-lease=disabled \
  -Degl=disabled -Dgles1=disabled -Dgles2=disabled -Dopengl=false \
  -Dglx=disabled -Dgbm=disabled -Dlibunwind=disabled -Dzstd=disabled \
  -Dcpp_link_args=-static-libstdc++ >"$LOG" 2>&1 || { tail -n 30 "$LOG"; die "meson setup (log $LOG)"; }
ninja -j"${JOBS:-$(nproc)}" -C "$BDIR" >>"$LOG" 2>&1 || { grep -E "error:|FAILED" "$LOG" | head -n 30; die "ninja (log $LOG)"; }
SO="$(find "$BDIR" -name libvulkan_panfrost.so | head -n1)"
[ -n "$SO" ] || die "libvulkan_panfrost.so not produced"
mkdir -p "$ROOT/dist"
cp "$SO" "$ROOT/dist/libvulkan_panfrost.so"
llvm-strip "$ROOT/dist/libvulkan_panfrost.so"
echo "OK dist/libvulkan_panfrost.so sha256=$(sha256sum "$ROOT/dist/libvulkan_panfrost.so" | cut -d' ' -f1)"
