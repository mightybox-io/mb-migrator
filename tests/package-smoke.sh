#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mb-package-test.XXXXXX")"
SOURCE="$TEST_ROOT/source"
TARGET="$TEST_ROOT/target"
FAKE_BIN="$TEST_ROOT/bin"
PACKAGE="$TEST_ROOT/portable-site.tar.gz"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$SOURCE/wp-content/plugins/sample-plugin" "$SOURCE/wp-content/themes/sample-theme" "$SOURCE/wp-content/uploads/2026/07"
mkdir -p "$TARGET/wp-content/plugins" "$TARGET/wp-content/themes" "$TARGET/wp-content/uploads" "$FAKE_BIN"
printf '%s\n' '<?php // plugin' > "$SOURCE/wp-content/plugins/sample-plugin/plugin.php"
printf '%s\n' '/* theme */' > "$SOURCE/wp-content/themes/sample-theme/style.css"
printf '%s\n' 'package upload' > "$SOURCE/wp-content/uploads/2026/07/package.txt"
printf '%s\n' 'verification' > "$SOURCE/verification.html"
printf '%s\n' '<?php core' > "$SOURCE/wp-load.php"
printf '%s\n' \
  '<?php' \
  "\$table_prefix = 'wp_';" > "$SOURCE/wp-config.php"
printf '%s\n' '<?php' "define('DB_NAME', 'target_db');" "\$table_prefix = 'wp_';" > "$TARGET/wp-config.php"

printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'cnf="${1#--defaults-extra-file=}"' \
  'grep -q '\''password="package-secret"'\'' "$cnf"' \
  'printf '\''/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;\nDROP TABLE IF EXISTS `wp_options`;\nCREATE TABLE `wp_options` (`option_id` bigint);\nINSERT INTO `wp_options` VALUES (1);\n/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;\n'\''' > "$FAKE_BIN/mariadb-dump"
printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf '\''https://source.example.test\n'\''' > "$FAKE_BIN/mariadb"
chmod +x "$FAKE_BIN/mariadb-dump" "$FAKE_BIN/mariadb"

export DB_NAME="source_db"
export DB_USER="source_user"
export DB_PASSWORD="package-secret"
export DB_HOST="localhost"
PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/bin/mb-migrator" export-site \
  --source-root="$SOURCE" \
  --output="$PACKAGE" \
  --db-method=native

test -s "$PACKAGE"
test -s "$PACKAGE.sha256"
tar -tzf "$PACKAGE" | grep -q '^mb-wordpress-package-manifest$'
tar -tzf "$PACKAGE" | grep -q '^database-package/site.sql$'
tar -tzf "$PACKAGE" | grep -q '^htdocs/wp-content/plugins/sample-plugin/plugin.php$'
if tar -tzf "$PACKAGE" | grep -q 'wp-config.php'; then
  printf 'portable package unexpectedly contains wp-config.php\n' >&2
  exit 1
fi
if tar -tzf "$PACKAGE" | grep -q 'wp-load.php'; then
  printf 'portable package unexpectedly contains WordPress core\n' >&2
  exit 1
fi

cp "$PACKAGE" "$TEST_ROOT/corrupt.tar.gz"
cp "$PACKAGE.sha256" "$TEST_ROOT/corrupt.tar.gz.sha256"
printf 'corrupt' >> "$TEST_ROOT/corrupt.tar.gz"
if PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/bin/mb-migrator" import-site "$TEST_ROOT/corrupt.tar.gz" \
  --target-root="$TARGET" --db-import=no >/dev/null 2>&1; then
  printf 'corrupt package unexpectedly passed checksum verification\n' >&2
  exit 1
fi

PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/bin/mb-migrator" import-site "$PACKAGE" \
  --target-root="$TARGET" \
  --new-url=https://destination.example.test \
  --db-import=no \
  --root-extras=copy \
  --mu-plugins=skip \
  --cleanup=no \
  --yes

test -f "$TARGET/wp-content/plugins/sample-plugin/plugin.php"
test -f "$TARGET/wp-content/themes/sample-theme/style.css"
test -f "$TARGET/wp-content/uploads/2026/07/package.txt"
test -f "$TARGET/verification.html"
grep -R -q 'Source URL read from package manifest: https://source.example.test' "$TARGET"/restore-*/migration-report.txt
grep -R -q 'URL rewrite pending' "$TARGET"/restore-*/migration-report.txt

printf 'portable package smoke test passed\n'
