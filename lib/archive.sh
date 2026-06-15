#!/usr/bin/env bash

ARCHIVE_INDEX=""

archive_index() {
  local archive="$1"
  local stage_dir="$2"
  ARCHIVE_INDEX="$stage_dir/.archive-index.txt"

  if [[ -s "$ARCHIVE_INDEX" ]]; then
    log "Using existing archive index: $ARCHIVE_INDEX"
    return 0
  fi

  log "Indexing archive contents"
  tar -tzf "$archive" > "$ARCHIVE_INDEX"
}

archive_has_path_prefix() {
  local prefix="$1"
  grep -Eq "^\./${prefix}(/|$)|^${prefix}(/|$)" "$ARCHIVE_INDEX"
}

archive_extract_existing_paths() {
  local archive="$1"
  local stage_dir="$2"
  shift 2

  local paths=()
  local path
  for path in "$@"; do
    if archive_has_path_prefix "$path"; then
      paths+=("./$path")
    else
      log "Archive path not present, skipping: $path"
    fi
  done

  if [[ "${#paths[@]}" -eq 0 ]]; then
    die "No requested archive paths exist"
  fi

  log "Extracting selected archive paths"
  tar -xzf "$archive" -C "$stage_dir" "${paths[@]}"
}
