#!/bin/sh
# Copy LQS into a server's modules lib folder.
#
#   tools/sync.sh <server lib folder> [--command <path for commands/quest.lua>] [--force]
#
# Copies lib/LQS.lua and lib/LQS/ (the C++ in cpp/ is per server: copy it by hand
# when you mean to). Records the LQS commit in <lib>/LQS/.synced. Refuses when the
# server's copy has changed since the last sync, so edits made there aren't lost:
# bring them back into LQS first, or pass --force to overwrite them.
set -e

REPO=$(cd "$(dirname "$0")/.." && pwd)
DEST=""
COMMAND=""
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --command) COMMAND="$2"; shift 2 ;;
        --force)   FORCE=1; shift ;;
        *)         DEST="$1"; shift ;;
    esac
done

if [ -z "$DEST" ] || [ ! -d "$DEST" ]; then
    echo "usage: tools/sync.sh <server lib folder> [--command <path>] [--force]" >&2
    exit 2
fi

STAMP="$DEST/LQS/.synced"

# Has the server's copy changed since the last sync?
if [ "$FORCE" -eq 0 ]; then
    if [ ! -f "$STAMP" ]; then
        if [ -e "$DEST/LQS.lua" ]; then
            echo "No $STAMP: can't tell whether the server's LQS was edited. Compare it, then use --force." >&2
            exit 1
        fi
    else
        LAST=$(cat "$STAMP")
        CHANGED=""

        for f in $(cd "$DEST" && find LQS.lua LQS -name '*.lua' 2>/dev/null); do
            if ! git -C "$REPO" show "$LAST:lib/$f" 2>/dev/null | cmp -s - "$DEST/$f"; then
                CHANGED="$CHANGED $f"
            fi
        done

        if [ -n "$CHANGED" ]; then
            echo "Changed in the server's copy since $LAST:$CHANGED" >&2
            echo "Bring those changes into LQS first, or use --force to overwrite them." >&2
            exit 1
        fi
    fi
fi

rm -rf "$DEST/LQS"
cp "$REPO/lib/LQS.lua" "$DEST/LQS.lua"
cp -r "$REPO/lib/LQS" "$DEST/LQS"

if [ -n "$COMMAND" ]; then
    cp "$REPO/commands/quest.lua" "$COMMAND"
fi

git -C "$REPO" rev-parse HEAD > "$STAMP"

if [ -n "$(git -C "$REPO" status --porcelain lib commands)" ]; then
    echo "Note: LQS has uncommitted changes in lib/ or commands/; the stamp names the last commit." >&2
fi

echo "LQS $(git -C "$REPO" describe --always --tags) copied to $DEST"
