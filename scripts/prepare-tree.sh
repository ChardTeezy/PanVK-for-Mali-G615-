#!/bin/sh
# prepare-tree.sh - apply the base PanVK-kbase stack, then the G615 MC2 patches, to work/mesa.
# Every patch must apply exactly (no fuzz). One commit per patch, so `git log` shows the series.
# Usage: scripts/prepare-tree.sh
set -eu
. "$(dirname "$0")/common.sh"
[ -d "$MESA_DIR/.git" ] && [ -d "$BASE_DIR/patches" ] || die "run scripts/fetch-sources.sh first"
[ "$(git -C "$MESA_DIR" rev-parse HEAD)" = "$(lock mesa.commit)" ] || die "$MESA_DIR must be at the pinned Mesa commit (re-run fetch-sources.sh)"
[ -z "$(git -C "$MESA_DIR" status --porcelain)" ] || die "$MESA_DIR is not clean"
git -C "$MESA_DIR" config user.name  "g615-mc2 build"
git -C "$MESA_DIR" config user.email "build@localhost"
CSF_MAX="$(lock base.csfMax)"; WIP_MAX="$(lock base.wipMax)"
P="$BASE_DIR/patches"

apply_one() { # patch label
  if git -C "$MESA_DIR" apply --check "$1" 2>/dev/null; then RC=""; else RC="--recount"; fi
  OUT="$(git -C "$MESA_DIR" apply $RC --check -v "$1" 2>&1)" || { echo "$OUT" >&2; die "$2 does not apply"; }
  if echo "$OUT" | grep -qiE 'offset|fuzz'; then echo "$OUT" | grep -iE 'offset|fuzz' >&2; die "$2 applies only with offset/fuzz"; fi
  git -C "$MESA_DIR" apply $RC "$1"
  git -C "$MESA_DIR" add -A
  git -C "$MESA_DIR" commit -q --no-verify -m "series: $2"
}

N=0
for fam in common android kbase-common app-loader wsi csf csf-v11 jm-v9 jm-v7; do
  for p in "$P/$fam"/*.patch; do
    [ -e "$p" ] || continue
    b="$(basename "$p")"
    if [ "$fam" = csf-v11 ] && [ "${b%%-*}" -gt "$CSF_MAX" ]; then continue; fi
    apply_one "$p" "$fam/$b"; N=$((N+1))
  done
  if [ -d "$P/$fam/files" ]; then
    (cd "$P/$fam/files" && find . -type f ! -name README -print0 | tar --null -cf - -T -) | (cd "$MESA_DIR" && tar -xf -)
    git -C "$MESA_DIR" add -A
    git -C "$MESA_DIR" commit -q --no-verify --allow-empty -m "series: $fam/files"
  fi
done
LAST=""
for p in "$P"/jm-v7-wip/0*.patch; do
  b="$(basename "$p")"
  [ "${b%%-*}" -le "$WIP_MAX" ] || continue
  git -C "$MESA_DIR" am -q "$p" || die "jm-v7-wip/$b does not apply"
  N=$((N+1)); LAST="${b%%-*}"
done
# driverInfo patch level read by bin/git_sha1_gen.py (jm-v7-wip 0154); kept out of the tree.
grep -qx '.panvk-patchlevel' "$MESA_DIR/.git/info/exclude" 2>/dev/null || echo '.panvk-patchlevel' >> "$MESA_DIR/.git/info/exclude"
[ -z "$LAST" ] || printf 'p%s\n' "$LAST" > "$MESA_DIR/.panvk-patchlevel"
git -C "$MESA_DIR" tag -f base-applied >/dev/null
echo "BASE-OK patches=$N"

# G615 MC2 layer
M=0
for p in "$ROOT"/patches/*.patch; do
  [ -e "$p" ] || continue
  apply_one "$p" "g615-mc2/$(basename "$p")"; M=$((M+1))
done

# Game profiles: overlay/ replaces 00-panvk-defaults.conf. Refuse if the base changed the file
# (re-run tools/gen_driconf.py against the new base and review the diff).
CONF=src/panfrost/vulkan/00-panvk-defaults.conf
EXPECT="$(python3 -c "import json;print(json.load(open('$ROOT/compat/game-profiles.json'))['baseConfSha256'])")"
HAVE="$(sha256sum "$MESA_DIR/$CONF" | cut -d' ' -f1)"
[ "$HAVE" = "$EXPECT" ] || die "base $CONF changed ($HAVE != $EXPECT): regenerate with tools/gen_driconf.py"
cp "$ROOT/overlay/$CONF" "$MESA_DIR/$CONF"
git -C "$MESA_DIR" add -A
git -C "$MESA_DIR" commit -q --no-verify -m "g615-mc2: per-game driconf profiles"
git -C "$MESA_DIR" tag -f g615-mc2-applied >/dev/null
echo "MC2-OK patches=$M head=$(git -C "$MESA_DIR" rev-parse --short HEAD)"
