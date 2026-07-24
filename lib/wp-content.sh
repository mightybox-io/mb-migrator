#!/usr/bin/env bash

merge_wp_content() {
  local source_wp_content="$1"
  local dest_wp_content="$2"

  [[ -d "$source_wp_content" ]] || die "Source wp-content not found: $source_wp_content"
  [[ -d "$dest_wp_content" ]] || die "Destination wp-content not found: $dest_wp_content"

  log "Overlaying staged plugins, themes, and uploads onto the destination"
  merge_wp_content_subdir "$source_wp_content" "$dest_wp_content" "plugins"
  merge_wp_content_subdir "$source_wp_content" "$dest_wp_content" "themes"
  merge_wp_content_subdir "$source_wp_content" "$dest_wp_content" "uploads"

  if [[ "${INCLUDE_MU_PLUGINS:-0}" -eq 1 ]]; then
    merge_wp_content_subdir "$source_wp_content" "$dest_wp_content" "mu-plugins"
  fi
}

merge_wp_content_subdir() {
  local source_wp_content="$1"
  local dest_wp_content="$2"
  local subdir="$3"
  local src="$source_wp_content/$subdir"
  local dest="$dest_wp_content/$subdir"

  if [[ ! -d "$src" ]]; then
    log "No exported wp-content/$subdir directory; skipping"
    return 0
  fi

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    log "Would merge $src -> $dest"
    return 0
  fi

  mkdir -p "$dest"

  local item name dest_item item_list
  item_list="$dest/.mb-migrator-items.$$"
  find "$src" -mindepth 1 -maxdepth 1 -print > "$item_list"

  while IFS= read -r item; do
    name="$(basename "$item")"
    dest_item="$dest/$name"

    if [[ "$subdir" == "plugins" ]] && is_platform_plugin_excluded "$name"; then
      log "Skipping platform-managed plugin: $name"
      report "Skipped platform-managed plugin: $name"
      continue
    fi

    if [[ -L "$dest_item" && "${REPLACE_MANAGED_SYMLINKS:-0}" -ne 1 ]]; then
      log "Preserving destination symlink: $dest_item"
      report "Preserved destination symlink: $dest_item"
      continue
    fi

    if [[ -d "$item" ]]; then
      mkdir -p "$dest_item"
      rsync -rlt --perms --chmod=Du=rwx,Dgo=rx,Fu=rw,Fgo=r \
        --no-owner --no-group --omit-dir-times "$item/" "$dest_item/"
    else
      rsync -rlt --perms --chmod=Fu=rw,Fgo=r \
        --no-owner --no-group --omit-dir-times "$item" "$dest/"
    fi
  done < "$item_list"
  rm -f "$item_list"

  report "Merged wp-content/$subdir from $src to $dest"
}

is_platform_plugin_excluded() {
  local plugin_slug="$1"

  case "$plugin_slug" in
    nginx-helper|redis-cache|redis-object-cache|redis-cache-pro|gridpane-redis-object-cache|wp-redis|wp-redis-cache|object-cache-pro|*redis*object*cache*)
      return 0
      ;;
  esac

  return 1
}

copy_web_root_files() {
  local source_web_root="$1"
  local target_root="$2"
  shift 2

  if [[ "$#" -eq 0 ]]; then
    log "No selected root-level extra files to copy"
    return 0
  fi

  [[ -d "$source_web_root" ]] || die "Source web root not found: $source_web_root"
  [[ -d "$target_root" ]] || die "Target root not found: $target_root"

  log "Copying root-level extra files"

  local archive_path relative_name source_file target_file
  for archive_path in "$@"; do
    relative_name="${archive_path#*/}"
    source_file="$source_web_root/$relative_name"
    target_file="$target_root/$relative_name"

    if [[ ! -f "$source_file" ]]; then
      log "Expected root-level file not found after extraction: $source_file"
      report "Missing extracted root-level file: $source_file"
      continue
    fi

    if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
      log "Would copy $source_file -> $target_file"
      continue
    fi

    rsync -lt --perms --chmod=Fu=rw,Fgo=r \
      --no-owner --no-group --omit-dir-times "$source_file" "$target_file"
    report "Copied root-level file from $source_file to $target_file"
  done
}
