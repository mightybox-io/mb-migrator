#!/usr/bin/env bash

wpcli_import_db() {
  local target_root="$1"
  local sql_file="$2"
  local skip_backup="$3"
  local delete_sql_after_import="$4"

  need_cmd wp
  [[ -f "$sql_file" ]] || die "SQL file not found: $sql_file"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log "Would import database: wp --path=$target_root db import $sql_file"
    return 0
  fi

  if [[ "$skip_backup" -ne 1 ]]; then
    local backup="$target_root/db-backup-before-import-$(date +%Y%m%d%H%M%S).sql"
    log "Backing up current database to $backup"
    wp --path="$target_root" db export "$backup"
    report "Database backup before import: $backup"
  fi

  log "Importing database"
  wp --path="$target_root" db import "$sql_file"
  report "Imported database from $sql_file"
  DB_IMPORT_RAN=1

  if [[ "$delete_sql_after_import" -eq 1 ]]; then
    log "Deleting combined SQL after successful import: $sql_file"
    rm -f "$sql_file"
    report "Deleted combined SQL after successful import: $sql_file"
  fi
}

wpcli_maybe_import_db() {
  local target_root="$1"
  local sql_file="$2"
  local skip_backup="$3"
  local import_mode="$4"
  local delete_sql_after_import="$5"

  case "$import_mode" in
    yes)
      wpcli_import_db "$target_root" "$sql_file" "$skip_backup" "$delete_sql_after_import"
      ;;
    no)
      log "Skipping database import"
      report "Database import: skipped"
      ;;
    ask)
      if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
        log "Would ask whether to import the combined SQL into the target database; default answer is yes"
        log "Would import database: wp --path=$target_root db import $sql_file"
        if [[ "$delete_sql_after_import" -eq 1 ]]; then
          log "Would delete combined SQL after successful import: $sql_file"
        fi
        report "Database import: ask deferred by dry-run, default yes"
      elif confirm_default_yes "Import combined SQL into the database configured by $target_root/wp-config.php?"; then
        wpcli_import_db "$target_root" "$sql_file" "$skip_backup" "$delete_sql_after_import"
      else
        log "Skipping database import"
        report "Database import: skipped by user"
      fi
      ;;
    *)
      die "Invalid database import mode: $import_mode"
      ;;
  esac
}

wpcli_search_replace() {
  local target_root="$1"
  local old_url="$2"
  local new_url="$3"

  need_cmd wp

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    wp --path="$target_root" search-replace "$old_url" "$new_url" --all-tables-with-prefix --precise --recurse-objects --skip-columns=guid --dry-run
    return 0
  fi

  confirm "Run serialized-safe search-replace from $old_url to $new_url?" || die "Search-replace cancelled"
  wp --path="$target_root" search-replace "$old_url" "$new_url" --all-tables-with-prefix --precise --recurse-objects --skip-columns=guid
  report "Ran search-replace from $old_url to $new_url"
}
