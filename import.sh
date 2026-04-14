#!/usr/bin/env bash

set -euo pipefail

# Mapping between folder names and OMERO usernames
declare -A USER_MAP=(
    ["David"]="DGordon"
    ["Emma"]="EScotter"
    ["Evelyn"]="EJade"
    ["Kyrah"]="KThumbadoo"
    ["Miran"]="MMrkela"
    ["Sebastian"]=""  # No matching user found
    ["Serey"]="SNaidoo"
    ["Sonalani"]="shsa310"
    ["Victor"]="VZhong"
)

BASE_DIR="/OMERO/DropBox"
STATE_DIR="/OMERO/.omero_import_state"

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
    local username="$2"
    local folder_name="$3"
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

    echo "$(date) Importing: $file (user: $username)" | tee -a "$LOG_FILE"

    if omero import \
        --transfer=ln_s \
        -s localhost:4064 \
        -u "$username" \
        --sudo root \
        -w "$ROOTPASS" \
        -T "regex:.+${folder_name}/(?<Container1>.*?)" \
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

# Process each user's folder
for folder_name in "${!USER_MAP[@]}"; do
    username="${USER_MAP[$folder_name]}"

    # Skip if no username mapping exists
    if [[ -z "$username" ]]; then
        echo "Skipping folder '$folder_name' - no OMERO user mapping found"
        continue
    fi

    source_dir="$BASE_DIR/$folder_name"

    # Skip if folder doesn't exist
    if [[ ! -d "$source_dir" ]]; then
        echo "Skipping '$folder_name' - directory does not exist: $source_dir"
        continue
    fi

    echo "Processing folder: $folder_name (user: $username)"

    # Process all files in this user's folder
    find "$source_dir" -mindepth 1 -type f ! -name 'Thumbs.db' -print0 | \
        xargs -0 -I{} -P "$PARALLEL" bash -c 'import_one "$1" "$2" "$3"' _ {} "$username" "$folder_name"
done
