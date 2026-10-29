#!/usr/bin/env bash

rollback_prepare() {
  local target_root="$1"
  if [[ -z "${ROLLBACK_DIR:-}" ]]; then
    ROLLBACK_DIR="$(mktemp -d "${MB_MIGRATOR_ROLLBACK_ROOT:-${TMPDIR:-/tmp}}/mb-migrator-rollback.XXXXXX")"
  else
    ROLLBACK_DIR="$(abs_path_for_create "$ROLLBACK_DIR")"
    [[ ! -e "$ROLLBACK_DIR" ]] || die "Rollback directory already exists: $ROLLBACK_DIR"
    mkdir -p "$ROLLBACK_DIR"
  fi
  ROLLBACK_DIR="$(cd "$ROLLBACK_DIR" && pwd -P)"
  target_root="$(cd "$target_root" && pwd -P)"
  case "$ROLLBACK_DIR/" in "$target_root/"*) die "Rollback directory must be outside the document root" ;; esac
  chmod 700 "$ROLLBACK_DIR"
  mkdir -p "$ROLLBACK_DIR/files"
  printf '%s\n' "$target_root" > "$ROLLBACK_DIR/target-root"
  : > "$ROLLBACK_DIR/added-files"
  chmod 600 "$ROLLBACK_DIR/target-root" "$ROLLBACK_DIR/added-files"
  log "Retaining overwritten files and database backup in: $ROLLBACK_DIR"
}

rollback_record_added() {
  local source="$1" dest="$2" relative="$3" path suffix
  if [[ -d "$source" && ! -L "$source" ]]; then
    find "$source" \( -type f -o -type l \) -print0 > "$ROLLBACK_DIR/.source-files"
    while IFS= read -r -d '' path; do
      suffix="${path#"$source"/}"
      rollback_record_path "$dest/$suffix" "$relative/$suffix"
    done < "$ROLLBACK_DIR/.source-files"
    rm -f "$ROLLBACK_DIR/.source-files"
  elif [[ ! -e "$dest" && ! -L "$dest" && -f "$source" ]]; then
    rollback_record_path "$dest" "$relative"
  fi
}

rollback_record_path() {
  local dest="$1" relative="$2" parent remaining
  [[ ! -e "$dest" && ! -L "$dest" ]] || return 0
  parent="$(dirname "$dest")"
  remaining="$relative"
  while [[ "$remaining" == */* ]]; do
    [[ ! -L "$parent" ]] || return 0
    parent="$(dirname "$parent")"
    remaining="${remaining%/*}"
  done
  printf '%s\0' "$relative" >> "$ROLLBACK_DIR/added-files"
}
