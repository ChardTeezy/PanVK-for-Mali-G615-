#!/bin/sh
# fetch-sources.sh - fetch the pinned base patch stack and the pinned Mesa commit.
# Usage: scripts/fetch-sources.sh            (uses work/ by default; WORK=... to change)
set -eu
. "$(dirname "$0")/common.sh"
mkdir -p "$WORK"

fetch_commit() { # dir url commit [extra fetch args]
  if [ ! -d "$1/.git" ]; then git init -q "$1"; git -C "$1" remote add origin "$2"; fi
  git -C "$1" fetch -q --depth 1 ${4:-} origin "$3"
  git -C "$1" checkout -q --detach FETCH_HEAD
  [ "$(git -C "$1" rev-parse HEAD)" = "$3" ] || die "$1 is not at $3"
}

# The base repository is large (device logs); only its patches/ and meson/ are needed.
if [ ! -d "$BASE_DIR/.git" ]; then
  git init -q "$BASE_DIR"
  git -C "$BASE_DIR" remote add origin "$(lock base.url)"
  git -C "$BASE_DIR" config core.sparseCheckout true
  printf 'patches/\nmeson/\nsources.lock\nLICENSES/\nNOTICE.md\n' > "$BASE_DIR/.git/info/sparse-checkout"
fi
# --filter=blob:none: only the blobs of the sparse paths are downloaded (~20 MB instead of ~1 GB).
fetch_commit "$BASE_DIR" "$(lock base.url)" "$(lock base.commit)" --filter=blob:none
BASE_MESA="$(python3 -c "import json;print(json.load(open('$BASE_DIR/sources.lock'))['mesaCommit'])")"
[ "$BASE_MESA" = "$(lock mesa.commit)" ] || die "base pins Mesa $BASE_MESA, sources.lock.json pins $(lock mesa.commit)"

fetch_commit "$MESA_DIR" "$(lock mesa.url)" "$(lock mesa.commit)"
echo "OK base=$(lock base.commit) mesa=$(lock mesa.commit)"
