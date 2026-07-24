#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mb-push-test.XXXXXX")"
STATE_DIR="$TEST_ROOT/state"
SOURCE="$TEST_ROOT/source"
FAKE_BIN="$TEST_ROOT/bin"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$SOURCE/wp-content/plugins/sample-plugin" "$FAKE_BIN"
printf '%s\n' '<?php // plugin' > "$SOURCE/wp-content/plugins/sample-plugin/plugin.php"
printf '%s\n' '<?php' "\$table_prefix = 'wp_';" > "$SOURCE/wp-config.php"

printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '[[ " $* " == *" -G "* ]] && exit 1' \
  'command_text="${!#}"' \
  'case "$command_text" in' \
  '  true) exit 0 ;;' \
  '  *"__MB_REMOTE_DIR__"*) printf '\''__MB_REMOTE_DIR__=/home/destination/.local/state/mb-migrator/incoming/push.test123\n'\'' ;;' \
  '  *"rm -f"*) printf '\''%s\n'\'' "$command_text" > "$PUSH_CLEANUP_MARKER" ;;' \
  '  *"remote-run.sh"*) printf '\''%s\n'\'' "$command_text" > "$PUSH_IMPORT_MARKER" ;;' \
  '  *) printf '\''unexpected fake ssh command: %s\n'\'' "$command_text" >&2; exit 1 ;;' \
  'esac' > "$FAKE_BIN/ssh"

printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '[[ "$*" == *wordpress-package.tar.gz* ]]' \
  '[[ "$*" == *wordpress-package.tar.gz.sha256* ]]' \
  '[[ "$*" == *remote-run.sh* ]]' \
  'printf '\''%s\n'\'' "$*" > "$PUSH_SCP_MARKER"' > "$FAKE_BIN/scp"

printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'host="${!#}"' \
  'public_key="$(awk '\''{print $1 " " $2; exit}'\'' "$PUSH_SCAN_KEY")"' \
  'printf '\''[%s]:3022 %s\n'\'' "$host" "$public_key"' > "$FAKE_BIN/ssh-keyscan"

printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'cnf="${1#--defaults-extra-file=}"' \
  'grep -q '\''password="push-secret"'\'' "$cnf"' \
  'printf '\''DROP TABLE IF EXISTS `wp_options`;\nCREATE TABLE `wp_options` (`option_id` bigint);\nINSERT INTO `wp_options` VALUES (1);\n'\''' > "$FAKE_BIN/mariadb-dump"

printf '%s\n' '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'printf '\''https://source-push.example.test\n'\''' > "$FAKE_BIN/mariadb"
chmod +x "$FAKE_BIN/ssh" "$FAKE_BIN/scp" "$FAKE_BIN/ssh-keyscan" "$FAKE_BIN/mariadb-dump" "$FAKE_BIN/mariadb"

export DB_NAME="push_source"
export DB_USER="push_user"
export DB_PASSWORD="push-secret"
export DB_HOST="localhost"
export PUSH_IMPORT_MARKER="$TEST_ROOT/import-command"
export PUSH_CLEANUP_MARKER="$TEST_ROOT/cleanup-command"
export PUSH_SCP_MARKER="$TEST_ROOT/scp-command"
export MB_MIGRATOR_SSH_DIR="$TEST_ROOT/ssh"

prepare_output="$(PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/bin/mb-migrator" push-pair prepare "--state-dir=$STATE_DIR")"
pairing_id="$(printf '%s\n' "$prepare_output" | awk -F': ' '/Pairing ID:/{print $2; exit}')"
[[ "$pairing_id" =~ ^[a-f0-9]{20}$ ]]
test -s "$STATE_DIR/push-pairings/$pairing_id/id_ed25519"
test -s "$STATE_DIR/push-pairings/$pairing_id/id_ed25519.pub"
export PUSH_SCAN_KEY="$STATE_DIR/push-pairings/$pairing_id/id_ed25519.pub"

PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/bin/mb-migrator" push-pair complete \
  "$pairing_id" newuser@new.example.test \
  --port=3022 \
  "--state-dir=$STATE_DIR"
test -s "$MB_MIGRATOR_SSH_DIR/known_hosts"

PATH="$FAKE_BIN:$PATH" "$ROOT_DIR/bin/mb-migrator" push-site \
  "--pairing=$pairing_id" \
  "--state-dir=$STATE_DIR" \
  "--source-root=$SOURCE" \
  --source-db-method=native \
  --target-root=/home/newuser/htdocs \
  --new-url=https://destination-push.example.test \
  --target-db-method=native \
  --db-import=yes \
  --mu-plugins=skip \
  --root-extras=skip \
  --cleanup=no \
  --yes

test -s "$PUSH_SCP_MARKER"
test -s "$PUSH_IMPORT_MARKER"
test -s "$PUSH_CLEANUP_MARKER"
grep -q 'import-site' "$PUSH_IMPORT_MARKER"
grep -q -- '--target-root=/home/newuser/htdocs' "$PUSH_IMPORT_MARKER"
grep -q -- '--new-url=https://destination-push.example.test' "$PUSH_IMPORT_MARKER"

printf 'outbound push smoke test passed\n'
