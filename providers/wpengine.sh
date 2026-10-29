#!/usr/bin/env bash

wpengine_detect() {
  grep -Eq '^database-wpengine/site\.sql$' "$1" &&
    grep -Eq '^htdocs/wp-content/(plugins|themes|uploads)/' "$1"
}

wpengine_load_layout() {
  gridpane_load_layout "$1"
  GRIDPANE_DB_DIR="database-wpengine"
  GRIDPANE_WP_CONFIG_PATH=""
  GRIDPANE_USER_CONFIGS_PATH=""
  report "WP Engine backup: wp-content/mysql.sql mapped to database-wpengine/site.sql"
}
wpengine_select_optional_paths() { gridpane_select_optional_paths "$@"; }
wpengine_extract() { gridpane_extract "$@"; }
wpengine_publish_layout() { gridpane_publish_layout; }
