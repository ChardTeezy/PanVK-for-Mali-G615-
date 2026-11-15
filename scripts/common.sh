# shellcheck shell=sh
# common.sh - shared paths and pins for the G615 MC2 build scripts (sourced, not run).
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$ROOT/work}"
BASE_DIR="${BASE_DIR:-$WORK/base}"
MESA_DIR="${MESA_DIR:-$WORK/mesa}"
LOCK="$ROOT/sources.lock.json"
lock() { python3 -c "import json,sys;d=json.load(open('$LOCK'));k=sys.argv[1].split('.');[d:=d[x] for x in k];print(d)" "$1"; }
die() { echo "ERROR: $*" >&2; exit 1; }
