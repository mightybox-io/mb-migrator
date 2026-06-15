#!/usr/bin/env bash

wpcli_import_db() {
  local target_root="$1"
  local sql_file="$2"
  local skip_backup="$3"

  need_cmd wp
  [[ -f "$sql_file" ]] || die "SQL file not found: $sql_file"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log "Would import database: wp --path=$target_root db import $sql_file"
    return 0
  fi

  confirm "Import combined SQL into the database configured by $target_root/wp-config.php?" || die "DB import cancelled"

  if [[ "$skip_backup" -ne 1 ]]; then
    local backup="$target_root/db-backup-before-import-$(date +%Y%m%d%H%M%S).sql"
    log "Backing up current database to $backup"
    wp --path="$target_root" db export "$backup"
    report "Database backup before import: $backup"
  fi

  log "Importing database"
  wp --path="$target_root" db import "$sql_file"
  report "Imported database from $sql_file"
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
