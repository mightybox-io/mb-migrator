#!/usr/bin/env bash

# Live legacy snapshots intentionally use the same safe on-disk shape as the
# original archive importer. The marker distinguishes snapshots produced by
# mb-migrator from third-party GridPane archives.

legacy_mightybox_detect() {
  local index_file="$1"
  grep -Eq '^\./mb-migrator-manifest$|^mb-migrator-manifest$' "$index_file" && \
    grep -Eq '^\./database-legacy/|^database-legacy/' "$index_file" && \
    grep -Eq '^\./htdocs/wp-content/|^htdocs/wp-content/' "$index_file"
}

legacy_mightybox_load_layout() {
  local index_file="$1"
  gridpane_load_layout "$index_file"
  GRIDPANE_DB_DIR="database-legacy"
  report "Legacy MightyBox snapshot marker: present"
}

legacy_mightybox_select_optional_paths() {
  gridpane_select_optional_paths "$@"
}

legacy_mightybox_extract() {
  gridpane_extract "$@"
}

legacy_mightybox_publish_layout() {
  gridpane_publish_layout
}
