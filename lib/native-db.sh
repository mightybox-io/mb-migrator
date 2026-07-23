#!/usr/bin/env bash

wp_config_value() {
  local target_root="$1" key="$2" type="${3:-constant}" value=""
  if command -v wp >/dev/null 2>&1; then
    if value="$(wp --path="$target_root" --skip-plugins --skip-themes config get "$key" --type="$type" --quiet 2>/dev/null)"; then
      printf '%s' "$value"
      return 0
    fi
  fi
  command -v php >/dev/null 2>&1 || return 1
  php -r '
    $text = file_get_contents($argv[1]);
    $key = preg_quote($argv[2], "/");
    $kind = $argv[3];
    if ($kind === "variable") {
      $pattern = "/\\$" . $key . "\\s*=\\s*([\\x27\\x22])((?:\\\\.|(?!\\1).)*)\\1\\s*;/s";
    } else {
      $pattern = "/define\\s*\\(\\s*[\\x27\\x22]" . $key . "[\\x27\\x22]\\s*,\\s*([\\x27\\x22])((?:\\\\.|(?!\\1).)*)\\1\\s*\\)/s";
    }
    if (preg_match($pattern, $text, $m)) { echo stripcslashes($m[2]); exit(0); }
    $envPattern = "/define\\s*\\(\\s*[\\x27\\x22]" . $key . "[\\x27\\x22]\\s*,\\s*getenv\\s*\\(\\s*([\\x27\\x22])([^\\x27\\x22]+)\\1\\s*\\)\\s*\\)/s";
    if ($kind === "constant" && preg_match($envPattern, $text, $m)) {
      $v = getenv($m[2]); if ($v !== false) { echo $v; exit(0); }
    }
    exit(1);
  ' "$target_root/wp-config.php" "$key" "$type"
}

native_ini_escape() {
  local value="$1"
  [[ "$value" != *$'\n'* && "$value" != *$'\r'* ]] || die "Database settings cannot contain newlines"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

native_db_create_config() {
  local target_root="$1" output="$2"
  local db_user db_password db_host host port socket
  NATIVE_DB_NAME="$(wp_config_value "$target_root" DB_NAME)" || die "Could not resolve DB_NAME from $target_root/wp-config.php"
  db_user="$(wp_config_value "$target_root" DB_USER)" || die "Could not resolve DB_USER from $target_root/wp-config.php"
  db_password="$(wp_config_value "$target_root" DB_PASSWORD)" || die "Could not resolve DB_PASSWORD from $target_root/wp-config.php"
  db_host="$(wp_config_value "$target_root" DB_HOST)" || die "Could not resolve DB_HOST from $target_root/wp-config.php"
  host="$db_host"; port=""; socket=""
  if [[ "$db_host" == *:/* ]]; then host="${db_host%%:*}"; socket="${db_host#*:}"
  elif [[ "$db_host" == *:* && "${db_host##*:}" =~ ^[0-9]+$ ]]; then host="${db_host%:*}"; port="${db_host##*:}"; fi
  umask 077
  {
    printf '[client]\nuser="%s"\npassword="%s"\nhost="%s"\n' "$(native_ini_escape "$db_user")" "$(native_ini_escape "$db_password")" "$(native_ini_escape "$host")"
    [[ -z "$port" ]] || printf 'port=%s\n' "$port"
    [[ -z "$socket" ]] || printf 'socket="%s"\n' "$(native_ini_escape "$socket")"
  } > "$output"
  chmod 600 "$output"
}

native_db_dump_binary() {
  if command -v mariadb-dump >/dev/null 2>&1; then command -v mariadb-dump
  elif command -v mysqldump >/dev/null 2>&1; then command -v mysqldump
  else return 1; fi
}

native_db_client_binary() {
  if command -v mariadb >/dev/null 2>&1; then command -v mariadb
  elif command -v mysql >/dev/null 2>&1; then command -v mysql
  else return 1; fi
}

native_db_backup() (
  local target_root="$1" backup="$2" cnf dump_bin
  umask 077
  dump_bin="$(native_db_dump_binary)" || die "Neither mariadb-dump nor mysqldump is available"
  cnf="$(mktemp "${TMPDIR:-/tmp}/mb-migrator-target-db.XXXXXX")"
  trap 'rm -f "$cnf"' EXIT
  native_db_create_config "$target_root" "$cnf"
  if ! "$dump_bin" --defaults-extra-file="$cnf" --single-transaction --quick --skip-lock-tables --hex-blob --default-character-set=utf8mb4 "$NATIVE_DB_NAME" > "$backup"; then
    rm -f "$cnf" "$backup"
    die "Native target database backup failed"
  fi
  rm -f "$cnf"; chmod 600 "$backup"
  trap - EXIT
)

native_db_import() (
  local target_root="$1" sql_file="$2" cnf client_bin
  client_bin="$(native_db_client_binary)" || die "Neither mariadb nor mysql is available"
  cnf="$(mktemp "${TMPDIR:-/tmp}/mb-migrator-target-db.XXXXXX")"
  trap 'rm -f "$cnf"' EXIT
  native_db_create_config "$target_root" "$cnf"
  if ! "$client_bin" --defaults-extra-file="$cnf" "$NATIVE_DB_NAME" < "$sql_file"; then
    rm -f "$cnf"
    die "Native target database import failed"
  fi
  rm -f "$cnf"
  trap - EXIT
)
