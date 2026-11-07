#!/bin/sh
# Builds every window and tab on the 1.12 widget mock of tools/preview and
# fires every registered event: fails on any Lua error. Needs only lua5.1.
#   sh tests/ui_smoke.sh [repo root]
root=${1:-.}
out=$(lua5.1 "$root/tools/preview/scenes.lua" "$root" - 2>&1)
code=$?
printf '%s\n' "$out" | grep -v '^scene [a-z-]*$'
exit $code
