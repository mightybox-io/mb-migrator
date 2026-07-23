#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mb-native-db-test.XXXXXX")"
TARGET="$TEST_ROOT/target"
ENV_TARGET="$TEST_ROOT/env-target"
FAKE_BIN="$TEST_ROOT/bin"
trap 'rm -rf "$TEST_ROOT"' EXIT
mkdir -p "$TARGET" "$ENV_TARGET" "$FAKE_BIN"

printf '%s\n' \
  '<?php' \
  "define('DB_NAME', 'target_db');" \
  "define('DB_USER', 'target_user');" \
  "define('DB_PASSWORD', getenv('TARGET_DB_PASSWORD'));" \
  "define('DB_HOST', 'localhost:/tmp/mysql.sock');" \
  "\$table_prefix = 'wp_';" > "$TARGET/wp-config.php"
printf '%s\n' 'CREATE TABLE `wp_options` (`option_id` bigint);' > "$TEST_ROOT/import.sql"
printf '%s\n' '<?php' "\$table_prefix = 'wp_';" > "$ENV_TARGET/wp-config.php"

printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '[[ "$*" != *target-secret* ]]' \
  'cnf="${1#--defaults-extra-file=}"' \
  'grep -q '\''password="target-secret"'\'' "$cnf"' \
  'grep -q '\''socket="/tmp/mysql.sock"'\'' "$cnf"' \
  'printf '\''CREATE TABLE `backup_table` (`id` bigint);\n'\''' > "$FAKE_BIN/mariadb-dump"

printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '[[ "$*" != *target-secret* ]]' \
  'cnf="${1#--defaults-extra-file=}"' \
  'grep -q '\''password="target-secret"'\'' "$cnf"' \
  'grep -q '\''CREATE TABLE `wp_options`'\'' > "$NATIVE_IMPORT_MARKER"' > "$FAKE_BIN/mariadb"
chmod +x "$FAKE_BIN/mariadb-dump" "$FAKE_BIN/mariadb"

export TARGET_DB_PASSWORD="target-secret"
export NATIVE_IMPORT_MARKER="$TEST_ROOT/imported"
PATH="$FAKE_BIN:$PATH" bash -c '
  set -euo pipefail
  source "$1/lib/util.sh"
  source "$1/lib/native-db.sh"
  source "$1/lib/wp-cli.sh"
  TARGET_DB_METHOD=native
  DRY_RUN=0
  REPORT_FILE="$2/report"
  ASSUME_YES=1
  preflight_environment "$2/target" "" 1 0 native
  wpcli_import_db "$2/target" "$2/import.sql" 0 0
' bash "$ROOT_DIR" "$TEST_ROOT"

test -f "$NATIVE_IMPORT_MARKER"
backup="$(find "$TARGET" -name 'db-backup-before-import-*.sql' -type f | head -n 1)"
test -s "$backup"

export DB_NAME="environment_db"
export DB_USER="environment_user"
export DB_PASSWORD="environment-secret"
export DB_HOST="environment-db:3307"
PATH="$FAKE_BIN:$PATH" bash -c '
  set -euo pipefail
  source "$1/lib/util.sh"
  source "$1/lib/native-db.sh"
  [[ "$(wp_config_value "$2/env-target" DB_NAME)" == "environment_db" ]]
  [[ "$(wp_config_value "$2/env-target" DB_USER)" == "environment_user" ]]
  [[ "$(wp_config_value "$2/env-target" DB_PASSWORD)" == "environment-secret" ]]
  [[ "$(wp_config_value "$2/env-target" DB_HOST)" == "environment-db:3307" ]]
' bash "$ROOT_DIR" "$TEST_ROOT"

if grep -R -l -e 'target-secret' -e 'environment-secret' \
  "$TARGET" "$ENV_TARGET" "$TEST_ROOT/report" "$TEST_ROOT/import.sql" \
  --exclude=wp-config.php >/dev/null 2>&1; then
  printf 'native DB flow leaked the database password\n' >&2
  exit 1
fi

printf 'native database smoke test passed\n'
