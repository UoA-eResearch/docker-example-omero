#!/usr/bin/env bash

set -euo pipefail

SOURCE_DIR="/OMERO/DropBox/MMrkela"
STATE_DIR="$HOME/.omero_import_state"

DONE_FILE="$STATE_DIR/imported.txt"
FAILED_FILE="$STATE_DIR/failed.txt"
LOG_FILE="$STATE_DIR/import.log"
LOCK_FILE="$STATE_DIR/import.lock"

PARALLEL=4   # adjust to suit your server

mkdir -p "$STATE_DIR"
touch "$DONE_FILE" "$FAILED_FILE" "$LOG_FILE"

exec 9>"$LOCK_FILE"

import_one() {
    local folder="$1"
    local folder_name
    folder_name="$(basename "$folder")"

    flock 9

    if grep -Fxq "$folder" "$DONE_FILE"; then
        echo "Skipping already imported: $folder_name"
        flock -u 9
        return
    fi

    flock -u 9

    echo "$(date) Importing: $folder_name" | tee -a "$LOG_FILE"

    if omero import \
        --transfer=ln_s \
	--parallel-fileset=$PARALLEL \
        -s localhost:4064 \
        -u MMrkela \
        --sudo root \
        -w "$ROOTPASS" \
        -T "regex:.+MMrkela/(?<Container1>.*?)" \
        "$folder"
    then
        flock 9
        echo "$folder" >> "$DONE_FILE"
        flock -u 9
        echo "$(date) SUCCESS: $folder_name" | tee -a "$LOG_FILE"
    else
        flock 9
        echo "$folder" >> "$FAILED_FILE"
        flock -u 9
        echo "$(date) FAILED: $folder_name" | tee -a "$LOG_FILE"
    fi
}

export -f import_one
export ROOTPASS DONE_FILE FAILED_FILE LOG_FILE LOCK_FILE
export PATH=/opt/omero/server/OMERO.server/bin/:$PATH

find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -type d | \
    xargs -I{} -P "$PARALLEL" bash -c 'import_one "$@"' _ {}
