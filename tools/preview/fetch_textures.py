#!/usr/bin/env python3
"""Download the textures the preview scenes use into a local cache.

    python3 tools/preview/fetch_textures.py <scene dir> <cache dir>

Textures come from the community export of the client's interface art
(github.com/Gethe/wow-ui-textures). It is the modern client's art, close
enough to 1.12 for a layout preview; nothing here ships with the addon.
"""
import json
import os
import subprocess
import sys

BASE = "https://raw.githubusercontent.com/Gethe/wow-ui-textures/live/"


def candidates(path):
    parts = path.replace("\\", "/").split("/")
    if parts and parts[0].lower() == "interface":
        parts = parts[1:]
    if not parts:
        return []
    dirs, name = parts[:-1], parts[-1]
    if dirs and dirs[0].lower() == "icons":
        dirs = ["ICONS"] + dirs[1:]
    out = []
    for d in ("/".join(dirs), "/".join(x.upper() for x in dirs)):
        for n in (name, name.lower(), name.upper(), name.title()):
            for ext in (".PNG", ".png"):
                out.append((d + "/" if d else "") + n + ext)
    seen, uniq = set(), []
    for c in out:
        if c not in seen:
            seen.add(c)
            uniq.append(c)
    return uniq


CLASS_ATLAS = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
CLASS_CELLS = {"warrior": (0, 0), "mage": (1, 0), "rogue": (2, 0), "druid": (3, 0),
               "hunter": (0, 1), "shaman": (1, 1), "priest": (2, 1), "warlock": (3, 1),
               "paladin": (0, 2)}


def class_atlas(dest):
    """The modern export has no 1.12 class atlas: rebuild it from single icons."""
    from PIL import Image
    base = ("https://media.githubusercontent.com/media/timhul/ClassicSim/558f84ad787d2fbbea74808a8c942aab55b86caa/"
            "QML/Assets/classes/Ui-charactercreate-classes_%s.png")
    atlas = Image.new("RGBA", (256, 256), (0, 0, 0, 0))
    tmp = dest + ".part"
    for name, (cx, cy) in CLASS_CELLS.items():
        r = subprocess.run(["curl", "-sS", "-f", "--max-time", "20", "-o", tmp, base % name], capture_output=True)
        if r.returncode != 0:
            return False
        icon = Image.open(tmp).convert("RGBA").resize((64, 64), Image.LANCZOS)
        atlas.paste(icon, (cx * 64, cy * 64))
    os.remove(tmp)
    atlas.save(dest)
    return True


def key(path):
    return path.replace("\\", "/").lower().replace("/", "_") + ".png"


def main():
    scene_dir, cache = sys.argv[1], sys.argv[2]
    os.makedirs(cache, exist_ok=True)
    paths = set()
    for f in os.listdir(scene_dir):
        if not f.endswith(".json"):
            continue
        with open(os.path.join(scene_dir, f)) as fh:
            scene = json.load(fh)
        for o in scene["objects"]:
            if o.get("file"):
                paths.add(o["file"])
            bd = o.get("backdrop")
            if isinstance(bd, dict):
                for k in ("bgFile", "edgeFile"):
                    if bd.get(k):
                        paths.add(bd[k])
    missing = []
    # 1.12 ships one file per raid icon; the export has the 4x2 atlas.
    if any("RaidTargetingIcon_" in p for p in paths):
        paths.add("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    repo = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
    for p in sorted(paths):
        dest = os.path.join(cache, key(p))
        local = p.replace("\\", "/")
        if local.lower().startswith("interface/addons/tortoisebotsmanager/"):
            src = os.path.join(repo, local[len("interface/addons/tortoisebotsmanager/"):] + ".tga")
            if os.path.exists(src):
                from PIL import Image
                Image.open(src).save(dest)
                continue
        dest = os.path.join(cache, key(p))
        if os.path.exists(dest) or os.path.exists(dest + ".missing"):
            continue
        ok = False
        if p == CLASS_ATLAS:
            ok = class_atlas(dest)
        for c in ([] if ok else candidates(p)):
            r = subprocess.run(["curl", "-sS", "-f", "--max-time", "20", "-o", dest, BASE + c],
                               capture_output=True)
            if r.returncode == 0 and os.path.getsize(dest) > 0:
                ok = True
                break
        if not ok:
            if os.path.exists(dest):
                os.remove(dest)
            open(dest + ".missing", "w").close()
            missing.append(p)
    print("textures: %d known, %d missing" % (len(paths), len(missing)))
    for m in missing:
        print("  missing:", m)


if __name__ == "__main__":
    main()
