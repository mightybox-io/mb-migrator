#!/usr/bin/env bash

log() {
  printf '[importer] %s\n' "$*"
}

warn() {
  printf '[importer:warn] %s\n' "$*" >&2
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
  if [[ -n "${REPORT_FILE:-}" ]]; then
    printf '%s\n' "$*" >> "$REPORT_FILE"
  fi
}

confirm() {
  local prompt="$1"
  if [[ "${ASSUME_YES:-0}" -eq 1 ]]; then
    log "$prompt yes"
    return 0
  fi
  printf '[importer:prompt] %s\n' "$prompt" >&2
  printf '[importer:prompt] Answer [y/N]: ' >&2
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

preflight_environment() {
  local target_root="$1"
  local archive="${2:-}"
  local import_db="${3:-0}"
  local search_replace="${4:-0}"
  local missing=0
  local cmd

  log "Running environment preflight"
  report "Environment preflight:"
  log "Shell host: $(hostname 2>/dev/null || printf 'unknown')"
  log "Shell user: $(id -un 2>/dev/null || printf 'unknown')"
  log "Working directory: $(pwd)"
  log "Bash version: ${BASH_VERSION:-unknown}"
  report "Shell host: $(hostname 2>/dev/null || printf 'unknown')"
  report "Shell user: $(id -un 2>/dev/null || printf 'unknown')"
  report "Working directory: $(pwd)"
  report "Bash version: ${BASH_VERSION:-unknown}"

  for cmd in tar perl rsync grep sed awk find sort comm diff date head rm cp mkdir; do
    if command -v "$cmd" >/dev/null 2>&1; then
      report "Command $cmd: $(command -v "$cmd")"
    else
      warn "Required command not found: $cmd"
      report "Command $cmd: missing"
      missing=1
    fi
  done

  if [[ "$import_db" -eq 1 || "$search_replace" -eq 1 ]]; then
    if command -v wp >/dev/null 2>&1; then
      report "Command wp: $(command -v wp)"
    else
      warn "WP-CLI is required for --import-db or --search-replace but was not found"
      report "Command wp: missing"
      missing=1
    fi
  elif command -v wp >/dev/null 2>&1; then
    report "Command wp: $(command -v wp)"
  else
    report "Command wp: missing, OK unless --import-db or --search-replace is used"
  fi

  [[ "$missing" -eq 0 ]] || die "Preflight failed because required commands are missing"

  if [[ ! -d "$target_root" ]]; then
    die "Target root does not exist from this shell: $target_root"
  fi
  report "Target root exists: $target_root"

  if [[ -d "$target_root/wp-content" ]]; then
    report "Target wp-content exists: $target_root/wp-content"
  else
    warn "Target wp-content does not exist: $target_root/wp-content"
    report "Target wp-content missing: $target_root/wp-content"
  fi

  if [[ -f "$target_root/wp-config.php" ]]; then
    report "Target wp-config.php exists: $target_root/wp-config.php"
  else
    warn "Target wp-config.php does not exist: $target_root/wp-config.php"
    report "Target wp-config.php missing: $target_root/wp-config.php"
  fi

  if [[ -e "$target_root/__wp__" ]]; then
    report "Target uses symlinked/shared core marker: $target_root/__wp__"
  fi

  if [[ -e "$target_root/wp-load.php" ]]; then
    report "Target wp-load.php exists: $target_root/wp-load.php"
  else
    report "Target wp-load.php missing: $target_root/wp-load.php"
  fi

  if [[ -d "$target_root/wp-admin" || -d "$target_root/wp-includes" ]]; then
    report "Target has local WordPress core directories: yes"
  elif [[ -e "$target_root/__wp__" || -e "$target_root/wp-load.php" ]]; then
    report "Target has local WordPress core directories: no, shared/symlinked core layout detected"
  else
    report "Target has local WordPress core directories: no"
  fi

  if [[ -w "$target_root" ]]; then
    report "Target root writable by current user: yes"
  else
    warn "Target root is not writable by the current shell user: $target_root"
    report "Target root writable by current user: no"
  fi

  if [[ -n "$archive" ]]; then
    if [[ -f "$archive" && -r "$archive" ]]; then
      report "Archive readable: $archive"
    else
      die "Archive is not readable from this shell: $archive"
    fi
  fi

  if [[ -e /dev/fd ]]; then
    report "/dev/fd exists: yes"
  else
    report "/dev/fd exists: no, OK; mb-migrator does not require it"
  fi

  if df -h "$target_root" >/dev/null 2>&1; then
    report "Disk space for target root:"
    df -h "$target_root" >> "${REPORT_FILE:-/dev/null}" 2>/dev/null || true
  else
    warn "Could not read disk usage for $target_root; continuing"
    report "Disk space for target root: unavailable"
  fi

  if command -v wp >/dev/null 2>&1 && [[ -f "$target_root/wp-config.php" ]]; then
    report "WP-CLI site validation: skipped; database may not be imported yet"
  fi
}
