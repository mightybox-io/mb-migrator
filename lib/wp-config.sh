#!/usr/bin/env bash

wp_config_report() {
  local source_config="$1"
  local target_config="$2"
  local stage_dir="$3"
  local extra_file="$stage_dir/wp-config-extra-from-export.txt"
  local diff_file="$stage_dir/wp-config.diff"

  if [[ ! -f "$source_config" ]]; then
    log "No exported wp-config.php found"
    report "No exported wp-config.php found"
    return 0
  fi

  if [[ ! -f "$target_config" ]]; then
    log "Target wp-config.php not found; exported config is staged at $source_config"
    report "Target wp-config.php not found; exported config: $source_config"
    return 0
  fi

  log "Generating wp-config report"
  perl -ne 'print if /^\s*define\s*\(/ || /^\s*\$table_prefix\s*=/' "$source_config" > "$extra_file.export"
  perl -ne 'print if /^\s*define\s*\(/ || /^\s*\$table_prefix\s*=/' "$target_config" > "$extra_file.target"
  sort "$extra_file.export" > "$extra_file.export.sorted"
  sort "$extra_file.target" > "$extra_file.target.sorted"
  comm -23 "$extra_file.export.sorted" "$extra_file.target.sorted" > "$extra_file" || true
  diff -u "$target_config" "$source_config" > "$diff_file" || true

  report "wp-config exported constants not present in target: $extra_file"
  report "wp-config full diff: $diff_file"
  log "wp-config extra constants report: $extra_file"
  log "wp-config diff: $diff_file"
}

wp_config_migrate() {
  local source_config="$1"
  local target_config="$2"

  [[ -f "$source_config" ]] || die "Exported wp-config.php not found: $source_config"

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log "Would replace $target_config with $source_config"
    return 0
  fi

  confirm "Replace target wp-config.php with exported wp-config.php?" || die "wp-config migration cancelled"

  local backup="$target_config.backup-$(date +%Y%m%d%H%M%S)"
  if [[ -f "$target_config" ]]; then
    cp -p "$target_config" "$backup"
    log "Backed up target wp-config.php to $backup"
    report "Backed up target wp-config.php to $backup"
  fi
  cp -p "$source_config" "$target_config"
  log "Migrated exported wp-config.php to $target_config"
  report "Migrated exported wp-config.php to $target_config"
}
