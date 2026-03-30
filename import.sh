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
    local file="$1"

    flock 9

    if grep -Fxq "$file" "$DONE_FILE"; then
        echo "Skipping already imported: $file"
        flock -u 9
        return
    fi

    flock -u 9

    echo "$(date) Importing: $file" | tee -a "$LOG_FILE"

    if omero import \
        --transfer=ln_s \
	--parallel-fileset=$PARALLEL \
        -s localhost:4064 \
        -u MMrkela \
        --sudo root \
        -w "$ROOTPASS" \
        -T "regex:.+MMrkela/(?<Container1>.*?)" \
        "$file"
    then
        flock 9
        echo "$file" >> "$DONE_FILE"
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
export ROOTPASS DONE_FILE FAILED_FILE LOG_FILE LOCK_FILE
export PATH=/opt/omero/server/OMERO.server/bin/:$PATH

find "$SOURCE_DIR" -mindepth 1 -type f | \
    xargs -I{} -P "$PARALLEL" bash -c 'import_one "$@"' _ {}
