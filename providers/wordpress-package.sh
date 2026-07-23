#!/usr/bin/env bash

WORDPRESS_PACKAGE_MANIFEST="mb-wordpress-package-manifest"

wordpress_package_detect() {
  local index_file="$1"
  grep -Eq "^\./${WORDPRESS_PACKAGE_MANIFEST}$|^${WORDPRESS_PACKAGE_MANIFEST}$" "$index_file" && \
    grep -Eq '^\./database-package/|^database-package/' "$index_file" && \
    grep -Eq '^\./htdocs/wp-content/|^htdocs/wp-content/' "$index_file"
}

wordpress_package_load_layout() {
  local index_file="$1"
  gridpane_load_layout "$index_file"
  GRIDPANE_DB_DIR="database-package"
  GRIDPANE_WP_CONFIG_PATH=""
  GRIDPANE_USER_CONFIGS_PATH=""
  report "Portable WordPress package marker: present"
}

wordpress_package_select_optional_paths() {
  gridpane_select_optional_paths "$@"
}

wordpress_package_extract() {
  gridpane_extract "$@"
  archive_extract_existing_paths "$1" "$2" "$WORDPRESS_PACKAGE_MANIFEST"
}

wordpress_package_publish_layout() {
  gridpane_publish_layout
  PROVIDER_MANIFEST_PATH="$WORDPRESS_PACKAGE_MANIFEST"
}
