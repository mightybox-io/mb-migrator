#!/usr/bin/env bash

log() {
  printf '[importer] %s\n' "$*"
}

die() {
  printf '[importer:error] %s\n' "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Required command not found: $1"
}

abs_path() {
  local path="$1"
  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$(pwd)" "$path"
  fi
}

abs_path_for_create() {
  local path="$1"
  local parent base
  parent="$(dirname "$path")"
  base="$(basename "$path")"
  if [[ "$parent" == /* ]]; then
    printf '%s/%s\n' "$parent" "$base"
  else
    printf '%s/%s/%s\n' "$(pwd)" "$parent" "$base"
  fi
}

report() {
  printf '%s\n' "$*" >> "$REPORT_FILE"
}

confirm() {
  local prompt="$1"
  if [[ "${ASSUME_YES:-0}" -eq 1 ]]; then
    log "$prompt yes"
    return 0
  fi
  printf '%s [y/N] ' "$prompt"
  read -r answer
  case "$answer" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

run_or_dry() {
  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    printf '[dry-run]'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}
