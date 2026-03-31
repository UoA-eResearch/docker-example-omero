#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR="/OMERO/DropBox/MMrkela"
STATE_DIR="$HOME/.omero_import_state"

# Per-file done state is stored as marker files under DONE_DIR so that
# membership tests are O(1) filesystem lookups rather than O(N) grep scans.
DONE_DIR="$STATE_DIR/done"
FAILED_FILE="$STATE_DIR/failed.txt"
LOG_FILE="$STATE_DIR/import.log"
LOCK_FILE="$STATE_DIR/import.lock"

PARALLEL=4   # adjust to suit your server

mkdir -p "$STATE_DIR" "$DONE_DIR"
touch "$FAILED_FILE" "$LOG_FILE"

# One-time migration: convert a legacy imported.txt (which recorded directory
# paths) to per-file marker files so previously-imported files are not
# re-imported after upgrading to this version of the script.
LEGACY_DONE="$STATE_DIR/imported.txt"
if [[ -f "$LEGACY_DONE" ]]; then
    echo "Migrating legacy state file $LEGACY_DONE …"
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        if [[ -d "$entry" ]]; then
            find "$entry" -mindepth 1 -type f -print0 | \
                while IFS= read -r -d '' f; do
                    marker="$DONE_DIR${f}"
                    mkdir -p "$(dirname "$marker")"
                    touch "$marker"
                done
        elif [[ -f "$entry" ]]; then
            marker="$DONE_DIR${entry}"
            mkdir -p "$(dirname "$marker")"
            touch "$marker"
        fi
    done < "$LEGACY_DONE"
    mv "$LEGACY_DONE" "${LEGACY_DONE}.migrated"
    echo "Migration complete."
fi

exec 9>"$LOCK_FILE"

import_one() {
    local file="$1"
    # Marker path mirrors the absolute file path under DONE_DIR, e.g.
    # /OMERO/DropBox/MMrkela/sub/img.tif → $DONE_DIR/OMERO/DropBox/…/img.tif
    local marker="$DONE_DIR${file}"

    flock 9
    if [[ -f "$marker" ]]; then
        echo "Skipping already imported: $file"
        flock -u 9
        return
    fi
    flock -u 9

    echo "$(date) Importing: $file" | tee -a "$LOG_FILE"

    if omero import \
        --transfer=ln_s \
        -s localhost:4064 \
        -u MMrkela \
        --sudo root \
        -w "$ROOTPASS" \
        -T "regex:.+MMrkela/(?<Container1>.*?)" \
        "$file"
    then
        flock 9
        mkdir -p "$(dirname "$marker")"
        touch "$marker"
        flock -u 9
        echo "$(date) SUCCESS: $file" | tee -a "$LOG_FILE"
    else
        flock 9
        echo "$file" >> "$FAILED_FILE"
        flock -u 9
        echo "$(date) FAILED: $file" | tee -a "$LOG_FILE"
    fi
}

export -f import_one
export ROOTPASS DONE_DIR FAILED_FILE LOG_FILE LOCK_FILE
export PATH=/opt/omero/server/OMERO.server/bin/:$PATH

find "$SOURCE_DIR" -mindepth 1 -type f -print0 | \
    xargs -0 -I{} -P "$PARALLEL" bash -c 'import_one "$@"' _ {}
