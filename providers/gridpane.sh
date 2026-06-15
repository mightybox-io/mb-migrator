#!/usr/bin/env bash

GRIDPANE_DB_DIR=""
GRIDPANE_WEB_ROOT=""
GRIDPANE_ROOT_EXTRA_FILES=()
GRIDPANE_ROOT_EXTRA_CANDIDATES=()
GRIDPANE_MU_PLUGINS_PRESENT=0

gridpane_detect() {
  local index_file="$1"
  grep -Eq '^\./database-[^/]+/|^database-[^/]+/' "$index_file" && \
    grep -Eq '^\./htdocs/wp-content/|^htdocs/wp-content/' "$index_file"
}

gridpane_load_layout() {
  local index_file="$1"
  local root_file root_name root_files_list

  GRIDPANE_DB_DIR="$(grep -E '^\./database-[^/]+/|^database-[^/]+/' "$index_file" | head -n 1 | sed -E 's#^\./##; s#/(.*)$##')"
  GRIDPANE_WEB_ROOT="htdocs"
  GRIDPANE_ROOT_EXTRA_FILES=()
  GRIDPANE_ROOT_EXTRA_CANDIDATES=()
  GRIDPANE_MU_PLUGINS_PRESENT=0

  [[ -n "$GRIDPANE_DB_DIR" ]] || die "Could not find GridPane database-* directory in archive"
  grep -Eq '^\./htdocs/wp-content/|^htdocs/wp-content/' "$index_file" || die "Could not find htdocs/wp-content in archive"
  if grep -Eq '^\./htdocs/wp-content/mu-plugins(/|$)|^htdocs/wp-content/mu-plugins(/|$)' "$index_file"; then
    GRIDPANE_MU_PLUGINS_PRESENT=1
  fi

  root_files_list="${index_file}.root-files.$$"
  grep -E '^\./htdocs/[^/]+$|^htdocs/[^/]+$' "$index_file" > "$root_files_list" || true

  while IFS= read -r root_file; do
    root_file="${root_file#./}"
    root_name="${root_file#htdocs/}"

    if gridpane_is_auto_root_extra "$root_name"; then
      GRIDPANE_ROOT_EXTRA_FILES+=("$root_file")
    elif ! gridpane_is_core_root_file "$root_name"; then
      GRIDPANE_ROOT_EXTRA_CANDIDATES+=("$root_file")
    fi
  done < "$root_files_list"
  rm -f "$root_files_list"

  report "GridPane database directory: $GRIDPANE_DB_DIR"
  report "GridPane web root: $GRIDPANE_WEB_ROOT"
  report "GridPane mu-plugins present: $GRIDPANE_MU_PLUGINS_PRESENT"
  if [[ "${#GRIDPANE_ROOT_EXTRA_FILES[@]}" -gt 0 ]]; then
    report "GridPane auto root extra files: ${GRIDPANE_ROOT_EXTRA_FILES[*]}"
  else
    report "GridPane auto root extra files: none"
  fi
  if [[ "${#GRIDPANE_ROOT_EXTRA_CANDIDATES[@]}" -gt 0 ]]; then
    report "GridPane root extra candidates: ${GRIDPANE_ROOT_EXTRA_CANDIDATES[*]}"
  else
    report "GridPane root extra candidates: none"
  fi
}

gridpane_is_auto_root_extra() {
  local root_name="$1"
  [[ "$root_name" =~ [Vv][Ii][Rr][Uu][Ss][-_]?[Dd][Ii][Ee] || "$root_name" =~ ^[Vv][Dd][Cc][Oo][Nn][Nn][Ee][Cc][Tt]-[^/]+\.php$ ]]
}

gridpane_is_core_root_file() {
  local root_name="$1"

  case "$root_name" in
    index.php|license.txt|readme.html|wp-*.php|xmlrpc.php|wp-config.php)
      return 0
      ;;
  esac

  return 1
}

gridpane_select_optional_paths() {
  local mu_plugins_mode="$1"
  local root_extras_mode="$2"
  local candidate

  INCLUDE_MU_PLUGINS=0

  if [[ "$GRIDPANE_MU_PLUGINS_PRESENT" -eq 1 ]]; then
    case "$mu_plugins_mode" in
      copy)
        INCLUDE_MU_PLUGINS=1
        report "Selected mu-plugins: copy"
        ;;
      skip)
        report "Selected mu-plugins: skip"
        ;;
      ask)
        if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
          log "Would ask whether to copy exported wp-content/mu-plugins"
          report "Selected mu-plugins: ask deferred by dry-run"
        elif confirm "Copy exported wp-content/mu-plugins? They can be platform-specific."; then
          INCLUDE_MU_PLUGINS=1
          report "Selected mu-plugins: copy"
        else
          report "Selected mu-plugins: skip"
        fi
        ;;
    esac
  fi

  if [[ "${#GRIDPANE_ROOT_EXTRA_CANDIDATES[@]}" -eq 0 ]]; then
    report "Selected root extra candidates: none"
    return 0
  fi

  case "$root_extras_mode" in
    copy)
      GRIDPANE_ROOT_EXTRA_FILES+=("${GRIDPANE_ROOT_EXTRA_CANDIDATES[@]}")
      report "Selected root extra candidates: all"
      ;;
    skip)
      report "Selected root extra candidates: skip all"
      ;;
    ask)
      for candidate in "${GRIDPANE_ROOT_EXTRA_CANDIDATES[@]}"; do
        if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
          log "Would ask whether to copy root-level file: $candidate"
          report "Root extra candidate deferred by dry-run: $candidate"
        elif confirm "Copy non-core root file $candidate?"; then
          GRIDPANE_ROOT_EXTRA_FILES+=("$candidate")
          report "Selected root extra candidate: $candidate"
        else
          report "Skipped root extra candidate: $candidate"
        fi
      done
      ;;
  esac
}

gridpane_extract() {
  local archive="$1"
  local stage_dir="$2"
  local include_mu_plugins="$3"

  local paths=(
    "$GRIDPANE_DB_DIR"
    "$GRIDPANE_WEB_ROOT/wp-config.php"
    "$GRIDPANE_WEB_ROOT/wp-content/plugins"
    "$GRIDPANE_WEB_ROOT/wp-content/themes"
    "$GRIDPANE_WEB_ROOT/wp-content/uploads"
  )

  if [[ "$include_mu_plugins" -eq 1 ]]; then
    paths+=("$GRIDPANE_WEB_ROOT/wp-content/mu-plugins")
  fi

  if [[ "${#GRIDPANE_ROOT_EXTRA_FILES[@]}" -gt 0 ]]; then
    paths+=("${GRIDPANE_ROOT_EXTRA_FILES[@]}")
  fi

  archive_extract_existing_paths "$archive" "$stage_dir" "${paths[@]}"
}
