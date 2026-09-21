#!/usr/bin/env python3
"""
tools/package_addon.py

Packages the TortoiseBotsManager addon into a clean, ready-to-install zip file.
Creates a top-level folder 'TortoiseBotsManager/' inside the zip archive containing
all necessary runtime files (.lua, .toc, README, LICENSE) while excluding dev/CI files.

Usage:
  python3 tools/package_addon.py [--output /path/to/TortoiseBotsManager.zip]
"""

import argparse
import os
import sys
import zipfile

# Files and extensions to include in the addon package
INCLUDED_FILES = {
    "TortoiseBotsManager.toc",
    "Core.lua",
    "Constants.lua",
    "Utils.lua",
    "Comms.lua",
    "Roster.lua",
    "UI.lua",
    "Minimap.lua",
    "README.md",
    "LICENSE",
}


def package_addon(repo_root, output_path):
    print(f"Packaging TortoiseBotsManager from: {repo_root}")
    print(f"Target zip archive: {output_path}")

    # Ensure parent directory of output exists
    out_dir = os.path.dirname(os.path.abspath(output_path))
    if out_dir and not os.path.exists(out_dir):
        os.makedirs(out_dir, exist_ok=True)

    files_added = 0
    total_uncompressed_bytes = 0

    with zipfile.ZipFile(output_path, "w", zipfile.ZIP_DEFLATED) as zf:
        for root, dirs, files in os.walk(repo_root):
            # Exclude version control, CI, dev tooling, and tests
            dirs[:] = [d for d in dirs if d not in {".git", ".github", "tools", "tests", "__pycache__"}]

            for filename in sorted(files):
                # Only include designated runtime files or general lua/toc/xml/tga/blp assets
                rel_path = os.path.relpath(os.path.join(root, filename), repo_root)
                ext = os.path.splitext(filename)[1].lower()

                if filename in INCLUDED_FILES or ext in {".lua", ".toc", ".xml", ".tga", ".blp"}:
                    full_path = os.path.join(root, filename)
                    # Universal WoW addon directory convention: inside zip, root folder must be 'TortoiseBotsManager/'
                    arcname = os.path.join("TortoiseBotsManager", rel_path)
                    zf.write(full_path, arcname)
                    file_size = os.path.getsize(full_path)
                    total_uncompressed_bytes += file_size
                    files_added += 1
                    print(f"  + {arcname} ({file_size} bytes)")

    zip_size = os.path.getsize(output_path)
    print(f"\nSuccessfully created {output_path}")
    print(f"Total files: {files_added} | Uncompressed: {total_uncompressed_bytes} bytes | Archive size: {zip_size} bytes")


def main():
    parser = argparse.ArgumentParser(description="Package TortoiseBotsManager into a release zip archive.")
    parser.add_argument(
        "--output",
        default="TortoiseBotsManager.zip",
        help="Path for output zip file (default: TortoiseBotsManager.zip)"
    )
    args = parser.parse_args()

    repo_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    package_addon(repo_root, args.output)


if __name__ == "__main__":
    main()
