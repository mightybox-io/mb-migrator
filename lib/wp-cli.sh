#!/usr/bin/env bash

wpcli_import_db() {
  local target_root="$1"
  local sql_file="$2"
  local skip_backup="$3"
  local delete_sql_after_import="$4"

  [[ -f "$sql_file" ]] || die "SQL file not found: $sql_file"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log "Would import database from $target_root: wp db import $sql_file"
    return 0
  fi

  local method="${TARGET_DB_METHOD:-auto}"
  local backup="" wp_available=0
  command -v wp >/dev/null 2>&1 && wp_available=1
  if [[ "$method" == "wp-cli" && "$wp_available" -eq 0 ]]; then die "WP-CLI target DB method requested but wp is unavailable"; fi

  if [[ "$skip_backup" -ne 1 ]]; then
    backup="$target_root/db-backup-before-import-$(date +%Y%m%d%H%M%S).sql"
    log "Backing up current database to $backup"
    if [[ "$method" != "native" && "$wp_available" -eq 1 ]] && wp_in_root "$target_root" --skip-plugins --skip-themes db export "$backup"; then
      chmod 600 "$backup"
    elif [[ "$method" == "wp-cli" ]]; then
      die "WP-CLI target database backup failed"
    else
      warn "Using native target database backup"
      native_db_backup "$target_root" "$backup"
    fi
    report "Database backup before import: $backup"
  fi

  log "Importing database"
  if [[ "$method" != "native" && "$wp_available" -eq 1 ]] && wp_in_root "$target_root" --skip-plugins --skip-themes db import "$sql_file"; then
    report "Target database method: wp-cli"
  elif [[ "$method" == "wp-cli" ]]; then
    die "WP-CLI target database import failed"
  else
    warn "Using native target database import"
    native_db_import "$target_root" "$sql_file"
    report "Target database method: native"
  fi
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
        log "Would import database from $target_root: wp db import $sql_file"
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

  if ! command -v wp >/dev/null 2>&1; then
    warn "WP-CLI is unavailable; URL rewrite is pending"
    warn "Run later: cd '$target_root' && wp search-replace '$old_url' '$new_url' --all-tables-with-prefix --precise --recurse-objects --skip-columns=guid"
    report "URL rewrite pending: WP-CLI unavailable"
    return 0
  fi

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    wp_in_root "$target_root" search-replace "$old_url" "$new_url" --all-tables-with-prefix --precise --recurse-objects --skip-columns=guid --dry-run
    return 0
  fi

  confirm "Run serialized-safe search-replace from $old_url to $new_url?" || die "Search-replace cancelled"
  if ! wp_in_root "$target_root" search-replace "$old_url" "$new_url" --all-tables-with-prefix --precise --recurse-objects --skip-columns=guid; then
    warn "WP-CLI search-replace failed; URL rewrite is pending"
    report "URL rewrite pending: WP-CLI command failed"
    return 0
  fi
  report "Ran search-replace from $old_url to $new_url"
}
