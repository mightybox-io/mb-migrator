#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIXTURE_DIR="$ROOT_DIR/tests/fixtures"
ARCHIVE="$FIXTURE_DIR/gridpane-export.tar.gz"
TARGET="$FIXTURE_DIR/target-smoke"
STAGE="$FIXTURE_DIR/stage-smoke"

rm -rf "$TARGET" "$STAGE" "$ARCHIVE"
cleanup() {
  if [[ "${KEEP_SMOKE_ARTIFACTS:-0}" -ne 1 ]]; then
    rm -rf "$TARGET" "$STAGE" "$ARCHIVE"
  fi
}
trap cleanup EXIT

mkdir -p "$TARGET/wp-content/plugins" "$TARGET/wp-content/themes" "$TARGET/wp-content/uploads"
cp "$FIXTURE_DIR/target/wp-config.php" "$TARGET/wp-config.php"

tar -czf "$ARCHIVE" -C "$FIXTURE_DIR/gridpane-export" .

"$ROOT_DIR/bin/mb-migrator" doctor \
  --target-root="$TARGET" \
  --archive="$ARCHIVE"

"$ROOT_DIR/bin/mb-migrator" restore "$ARCHIVE" \
  --target-root="$TARGET" \
  --stage-dir="$STAGE" \
  --root-extras=copy \
  --mu-plugins=skip \
  --db-import=no

test -f "$TARGET/wp-content/plugins/sample-plugin/sample-plugin.php"
test ! -e "$TARGET/wp-content/plugins/nginx-helper/nginx-helper.php"
test ! -e "$TARGET/wp-content/plugins/redis-cache/redis-cache.php"
test ! -e "$TARGET/wp-content/plugins/gridpane-redis-object-cache/gridpane-redis-object-cache.php"
test -f "$TARGET/wp-content/themes/sample-theme/style.css"
test -f "$TARGET/wp-content/uploads/2026/06/sample.txt"
test -f "$TARGET/vdconnect-sp4460r4.php"
test -f "$TARGET/sitemap.xml"
test ! -e "$TARGET/wp-content/mu-plugins/platform-loader.php"
test -f "$STAGE/gridpane-export-combined-phpmyadmin-import.sql"
test -f "$STAGE/sample-archived-assets/wp-config.php"
test -f "$STAGE/sample-archived-assets/user-configs.php"
test -f "$STAGE/wp-config.diff"

perl -ne '
  $bad_tz++ if /TIME_ZONE\s*=\s*\+\d\d:\d\d/i;
  $create++ if /^\s*CREATE\s+TABLE\b/i;
  $drop++ if /^\s*DROP\s+TABLE\s+IF\s+EXISTS\b/i;
  $createdb++ if /^\s*CREATE\s+DATABASE\b/i;
  $use++ if /^\s*USE\s+/i;
  END { exit 1 if ($bad_tz||0) || ($createdb||0) || ($use||0) || (($create||0) != ($drop||0)); }
' "$STAGE/gridpane-export-combined-phpmyadmin-import.sql"

printf 'smoke test passed\n'
