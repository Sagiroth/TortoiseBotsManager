#!/bin/sh
# Render every preview scene: tools/preview/run.sh <out dir> <asset dir> [scene ...]
# <asset dir> must hold fonts/FRIZQT__.ttf and fonts/ARIALN.ttf (the client's
# fonts; not in the repo). Textures are downloaded into <asset dir>/tex.
set -e
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
out=$1; assets=$2; shift 2
mkdir -p "$out" "$assets/tex"
rm -f "$out"/*.json
lua5.1 "$here/scenes.lua" "$root" "$out"
# addon Media textures are converted fresh on every run
rm -f "$assets"/tex/interface_addons_tortoisebotsmanager_*
python3 "$here/fetch_textures.py" "$out" "$assets/tex"
node "$here/render.js" "$out" "$assets" "$@"
