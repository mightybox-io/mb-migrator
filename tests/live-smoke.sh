#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mb-migrator-live-test.XXXXXX")"
SOURCE="$TEST_ROOT/source"
TARGET="$TEST_ROOT/target"
STATE="$TEST_ROOT/state"
FAKE_BIN="$TEST_ROOT/bin"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$SOURCE/wp-content/plugins/sample-plugin" "$SOURCE/wp-content/themes/sample-theme" "$SOURCE/wp-content/uploads/2026/07"
mkdir -p "$TARGET/wp-content/plugins" "$TARGET/wp-content/themes" "$TARGET/wp-content/uploads" "$FAKE_BIN" "$STATE"

printf '%s\n' '<?php // plugin' > "$SOURCE/wp-content/plugins/sample-plugin/plugin.php"
printf '%s\n' '/* theme */' > "$SOURCE/wp-content/themes/sample-theme/style.css"
printf '%s\n' 'initial upload' > "$SOURCE/wp-content/uploads/2026/07/initial.txt"
printf '%s\n' 'verification' > "$SOURCE/verification.html"
printf '%s\n' '<?php core' > "$SOURCE/wp-load.php"
printf '%s\n' \
  '<?php' \
  "define('DB_NAME', 'legacy_db');" \
  "define('DB_USER', 'legacy_user');" \
  "define('DB_PASSWORD', getenv('LEGACY_DB_PASSWORD'));" \
  "define('DB_HOST', 'localhost:3307');" \
  "\$table_prefix = 'wp_';" > "$SOURCE/wp-config.php"
printf '%s\n' \
  '<?php' \
  "define('DB_NAME', 'target_db');" \
  "define('DB_USER', 'target_user');" \
  "define('DB_PASSWORD', 'target-secret');" \
  "define('DB_HOST', 'localhost');" \
  "\$table_prefix = 'wp_';" > "$TARGET/wp-config.php"

printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'while [[ $# -gt 0 ]]; do' \
  '  case "$1" in -p|-i|-o) shift 2 ;; *) break ;; esac' \
  'done' \
  'shift' \
  'if [[ "${1:-}" == command && "${2:-}" == -v && "${3:-}" == rsync ]]; then' \
  '  [[ "${FAKE_REMOTE_RSYNC:-0}" -eq 1 ]] && { printf '\''/usr/bin/rsync\n'\''; exit 0; }' \
  '  exit 1' \
  'fi' \
  'if [[ "${1:-}" == true ]]; then exit 0; fi' \
  'exec "$@"' > "$FAKE_BIN/ssh"

printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'cnf="${1#--defaults-extra-file=}"' \
  'test -f "$cnf"' \
  'grep -q '\''password="migration-secret"'\'' "$cnf"' \
  'printf '\''DROP TABLE IF EXISTS `wp_options`;\nCREATE TABLE `wp_options` (`option_id` bigint);\nINSERT INTO `wp_options` VALUES (1);\n'\''' > "$FAKE_BIN/mariadb-dump"
printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf '\''https://legacy.example.test\n'\''' > "$FAKE_BIN/mariadb"
printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '[[ "$*" != *--delete* ]]' \
  'previous=""; current=""' \
  'for item in "$@"; do previous="$current"; current="$item"; done' \
  'source_path="${previous#*:}"' \
  'if [[ "$previous" == *:* ]]; then' \
  '  mkdir -p "$current"; cp -R "${source_path%/}/." "$current/"' \
  '  [[ -z "${FAKE_RSYNC_MARKER:-}" ]] || touch "$FAKE_RSYNC_MARKER"' \
  'elif [[ -d "$source_path" ]]; then' \
  '  mkdir -p "$current"; cp -R "${source_path%/}/." "$current/"' \
  'else' \
  '  cp "$source_path" "$current"' \
  'fi' > "$FAKE_BIN/rsync"
chmod +x "$FAKE_BIN/ssh" "$FAKE_BIN/mariadb-dump" "$FAKE_BIN/mariadb" "$FAKE_BIN/rsync"
touch "$TEST_ROOT/key"; chmod 600 "$TEST_ROOT/key"

export LEGACY_DB_PASSWORD="migration-secret"
PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/bin/mb-migrator" doctor \
  --source=legacy@test \
  --source-root="$SOURCE" \
  --target-root="$TARGET" \
  --identity-file="$TEST_ROOT/key" \
  --state-dir="$STATE" \
  --source-db-method=native \
  --target-db-method=native

PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/bin/mb-migrator" pull legacy@test \
  --source-root="$SOURCE" \
  --target-root="$TARGET" \
  --identity-file="$TEST_ROOT/key" \
  --state-dir="$STATE" \
  --source-db-method=native \
  --new-url=https://new.example.test \
  --db-import=no \
  --root-extras=copy \
  --mu-plugins=skip \
  --cleanup=no \
  --yes

test -f "$TARGET/wp-content/plugins/sample-plugin/plugin.php"
test -f "$TARGET/wp-content/themes/sample-theme/style.css"
test -f "$TARGET/wp-content/uploads/2026/07/initial.txt"
test -f "$TARGET/verification.html"
test ! -f "$TARGET/wp-load.php"
grep -R -q 'URL rewrite pending' "$TARGET"/restore-*/migration-report.txt

snapshot="$(find "$STATE/migrations" -path '*/snapshots/*.tar.gz' -type f | head -n 1)"
test -n "$snapshot"
test -f "$snapshot.sha256"
if tar -tzf "$snapshot" | grep -q 'wp-config.php'; then
  printf 'live snapshot unexpectedly contains wp-config.php\n' >&2
  exit 1
fi
if grep -R -l 'migration-secret' "$STATE" >/dev/null 2>&1; then
  printf 'migration state leaked the database password\n' >&2
  exit 1
fi

printf '%s\n' 'catch-up upload' > "$SOURCE/wp-content/uploads/2026/07/catch-up.txt"
rm -f "$SOURCE/wp-content/uploads/2026/07/initial.txt"
PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/bin/mb-migrator" pull legacy@test \
  --source-root="$SOURCE" \
  --target-root="$TARGET" \
  --identity-file="$TEST_ROOT/key" \
  --state-dir="$STATE" \
  --source-db-method=native \
  --continue-existing \
  --db-import=no \
  --root-extras=copy \
  --mu-plugins=skip \
  --cleanup=no \
  --yes

test -f "$TARGET/wp-content/uploads/2026/07/catch-up.txt"
test -f "$TARGET/wp-content/uploads/2026/07/initial.txt"
grep -R -q 'URL rewrite pending' "$TARGET"/restore-*/migration-report.txt

printf '%s\n' 'rsync catch-up' > "$SOURCE/wp-content/uploads/2026/07/rsync.txt"
export FAKE_REMOTE_RSYNC=1
export FAKE_RSYNC_MARKER="$TEST_ROOT/rsync-ran"
PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/bin/mb-migrator" pull legacy@test \
  --source-root="$SOURCE" \
  --target-root="$TARGET" \
  --identity-file="$TEST_ROOT/key" \
  --state-dir="$STATE" \
  --source-db-method=native \
  --continue-existing \
  --db-import=no \
  --root-extras=copy \
  --mu-plugins=skip \
  --cleanup=no \
  --yes

test -f "$FAKE_RSYNC_MARKER"
test -f "$TARGET/wp-content/uploads/2026/07/rsync.txt"
test "$(find "$STATE/migrations" -path '*/snapshots/*.tar.gz' -type f | wc -l | tr -d ' ')" -eq 3

printf '%s\n' "define('MULTISITE', true);" >> "$SOURCE/wp-config.php"
if PATH="$FAKE_BIN:$PATH" bash "$ROOT_DIR/lib/remote-source.sh" preflight "$SOURCE" native >/dev/null 2>&1; then
  printf 'multisite preflight was expected to fail\n' >&2
  exit 1
fi

printf 'live migration smoke test passed\n'
