# MB Migrator

`mb-migrator` restores WordPress provider exports into a MightyBox-style WordPress document root.

It is built for migration work where a single provider export archive contains site files plus split SQL database dumps. The first supported provider adapter is GridPane-style SFTP exports. The project is intentionally modular so support for other providers can be added behind provider adapters.

It can also pull a single-site WordPress installation directly from a legacy MightyBox host over SSH. The live workflow is controlled entirely from the new host; the legacy host does not need a copy of this repository.

## Portable WordPress Packages

The portable package workflow works with any source and destination hosts where you can run shell commands. The hosts do not need direct network connectivity:

1. Run `export-site` on the old host.
2. Transfer the package and its checksum manually.
3. Run `import-site` on the new host.

The commands can be run without cloning this repository.

On the old host, create the package:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/mightybox-io/mb-migrator/main/remote-run.sh)" -- \
  export-site \
  --source-root=/path/to/wordpress \
  --output="$HOME/wordpress-package.tar.gz"
```

Database export defaults to `auto`, which tries WP-CLI first and then native `mariadb-dump`/`mysqldump` using credentials resolved from `wp-config.php`. Force a method when troubleshooting:

```bash
--db-method=wp-cli
--db-method=native
```

The export produces:

```text
wordpress-package.tar.gz
wordpress-package.tar.gz.sha256
```

Transfer both files using `scp`, SFTP, your laptop, or any other approved method. For example, from a workstation that can reach both hosts:

```bash
scp -P 3022 user@old-host:~/wordpress-package.tar.gz* .
scp wordpress-package.tar.gz* user@new-host:~/
```

On the new host, verify and import the package:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/mightybox-io/mb-migrator/main/remote-run.sh)" -- \
  import-site "$HOME/wordpress-package.tar.gz" \
  --target-root=/srv/htdocs \
  --new-url=https://new.example.com
```

`import-site` verifies the checksum when the sidecar is present, reads the old URL from the package manifest when it was detectable, and then uses the normal guarded restore pipeline. If export could not detect the source URL, pass `--old-url` together with `--new-url`. Import prompts for database import, `mu-plugins`, root extras, and cleanup unless explicit policies are supplied.

For an unattended import:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/mightybox-io/mb-migrator/main/remote-run.sh)" -- \
  import-site "$HOME/wordpress-package.tar.gz" \
  --target-root=/srv/htdocs \
  --new-url=https://new.example.com \
  --target-db-method=auto \
  --mu-plugins=skip \
  --root-extras=copy \
  --db-import=yes \
  --cleanup=no \
  --yes
```

Portable packages contain the database, `wp-content`, non-core root-file candidates, and source URL metadata. They exclude WordPress core and `wp-config.php`. Package files use mode `0600`, and temporary work directories use mode `0700`. The source host needs temporary free space for an extracted copy of the selected site files plus the final compressed package.

## Live Legacy MightyBox Migration

Legacy sites are expected at `/var/www/webroot/ROOT` by default. Run the migrator from the new host as the user that can write the destination WordPress root.

### One-Line Remote Use

The repository does not need to be cloned onto the new host. Each command downloads a temporary copy of the migrator, while SSH keys, migration state, and retained snapshots remain in the new host user's private state directory.

Pair the new host with the legacy host:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/mightybox-io/mb-migrator/main/remote-run.sh)" -- \
  pair user@legacy-host
```

Preflight both hosts:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/mightybox-io/mb-migrator/main/remote-run.sh)" -- \
  doctor \
  --source=user@legacy-host \
  --source-root=/var/www/webroot/ROOT \
  --target-root=/srv/htdocs
```

Run the migration:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/mightybox-io/mb-migrator/main/remote-run.sh)" -- \
  pull user@legacy-host \
  --source-root=/var/www/webroot/ROOT \
  --target-root=/srv/htdocs \
  --new-url=https://new.example.com
```

Run the same migration again as a catch-up before cutover:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/mightybox-io/mb-migrator/main/remote-run.sh)" -- \
  pull user@legacy-host \
  --source-root=/var/www/webroot/ROOT \
  --target-root=/srv/htdocs \
  --continue-existing
```

Set `MB_MIGRATOR_REF` before the command to run a specific branch, tag, or commit instead of `main`.

Pair the hosts first:

```bash
./bin/mb-migrator pair user@legacy-host
```

The command creates a dedicated Ed25519 key and attempts to install it with `ssh-copy-id`. If password-based installation is unavailable, it prints a public-key command to run from an authorized SSH session on the legacy host. Existing keys can be used with `--identity-file`.

Preflight both hosts without transferring the site:

```bash
./bin/mb-migrator doctor \
  --source=user@legacy-host \
  --source-root=/var/www/webroot/ROOT \
  --target-root=/srv/htdocs
```

Pull and restore the site:

```bash
./bin/mb-migrator pull user@legacy-host \
  --source-root=/var/www/webroot/ROOT \
  --target-root=/srv/htdocs \
  --old-url=https://legacy.example.com \
  --new-url=https://example.com \
  --db-import=yes \
  --yes
```

When `--new-url` is supplied without `--old-url`, the migrator tries to read the source home URL with WP-CLI and then with a native database query. Serialized-safe URL replacement runs on the new host. If WP-CLI is unavailable there, migration completes with a prominent “URL rewrite pending” warning and the follow-up command is written to the report.

### Catch-up Runs

Migration state is identified by source host, SSH port, source root, and target root. Repeating the same pull interactively prompts to continue the existing migration, restart it, or cancel. For unattended operation, choose explicitly:

```bash
./bin/mb-migrator pull user@legacy-host \
  --target-root=/srv/htdocs \
  --continue-existing \
  --db-import=yes \
  --yes
```

A catch-up always takes a fresh full database dump. When `rsync` exists on both hosts, only new and changed files cross SSH. Otherwise, the migrator automatically retransfers a complete tar snapshot. Source deletions are never propagated to the destination.

Detected or supplied old/new URLs are saved in the private migration state and automatically reused during catch-up, so importing the fresh database does not undo the destination URL rewrite.

Use `--restart` to delete only the matching migration state and begin again. In an interactive session the exact state path is shown before restart. `--yes` by itself never selects this destructive action.

### Database Fallback

Source export and target backup/import support:

```text
--source-db-method=auto|wp-cli|native
--target-db-method=auto|wp-cli|native
```

`auto` tries WP-CLI first and falls back to `mariadb-dump`/`mysqldump` or `mariadb`/`mysql`. Native mode reads `DB_NAME`, `DB_USER`, `DB_PASSWORD`, and `DB_HOST` from `wp-config.php` without bootstrapping WordPress. Quoted literals and simple `getenv('NAME')` values are supported, including host ports and Unix sockets. Unsupported dynamic expressions fail preflight with the unresolved setting named.

Credentials are written only to temporary mode-`0600` client files and are never placed in process arguments, reports, snapshots, or saved migration state. The live snapshot also excludes `wp-config.php`.

### State and Consistency

Private state defaults to `$XDG_STATE_HOME/mb-migrator` or `$HOME/.local/state/mb-migrator`. State directories use mode `0700`; keys, dumps, manifests, and snapshots use mode `0600`. Successful snapshots are retained by default for retry and audit. Pass `--snapshot=delete` to remove the snapshot after a successful restore.

Version one supports WordPress single-site installations. Multisite is rejected during preflight. A live site can change while files and database are collected, so the recommended cutover is an initial pull followed by a catch-up immediately before DNS or proxy cutover, after pausing content changes when possible.

## One-Line Remote Run

Run without installing the repo first:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/mightybox-io/mb-migrator/main/remote-run.sh)" -- restore /path/to/export.tar.gz --target-root=/srv/htdocs --dry-run
```

The remote runner downloads the repo into a temporary directory, runs `bin/mb-migrator`, then removes the temporary directory when it exits.

Use a branch, tag, or commit by setting `MB_MIGRATOR_REF`:

```bash
MB_MIGRATOR_REF=main bash -c "$(curl -fsSL https://raw.githubusercontent.com/mightybox-io/mb-migrator/main/remote-run.sh)" -- restore /path/to/export.tar.gz --target-root=/srv/htdocs --dry-run
```

## Local Usage

```bash
./bin/mb-migrator --help
```

Run a preflight check from the SSH shell before restoring:

```bash
./bin/mb-migrator doctor \
  --target-root=/srv/htdocs \
  --archive=/path/to/export.tar.gz
```

Dry run first:

```bash
./bin/mb-migrator restore /path/to/export.tar.gz \
  --target-root=/srv/htdocs \
  --dry-run
```

Restore files and build the combined SQL file:

```bash
./bin/mb-migrator restore /path/to/export.tar.gz \
  --target-root=/srv/htdocs
```

Restore, automatically import the DB, and run serialized-safe search-replace:

```bash
./bin/mb-migrator restore /path/to/export.tar.gz \
  --target-root=/srv/htdocs \
  --old-url=https://old.example.com \
  --new-url=https://new.example.com \
  --db-import=yes \
  --search-replace
```

The old command name still works for compatibility:

```bash
./bin/wp-export-migrate --help
```

## What It Does

For GridPane-style exports, `mb-migrator` will:

- Detect the provider layout from the archive contents.
- Extract selected paths into a timestamped staging directory.
- Merge `wp-content/plugins`, `wp-content/themes`, and `wp-content/uploads` into the target site.
- Preserve existing destination symlinks by default, which avoids replacing platform-managed plugin/theme symlinks.
- Detect and copy root-level Virusdie connector files such as `vdconnect-*.php` automatically.
- Detect other non-core root files and ask one-by-one before copying them by default.
- Detect `wp-content/mu-plugins` and ask separately before copying because `mu-plugins` are often platform-specific.
- Combine split SQL database files into one importable SQL file.
- Generate `wp-config.php` reports and diffs without changing the target config by default.
- Optionally import the combined SQL with WP-CLI.
- Optionally run serialized-safe WP-CLI search-replace.
- Write a migration report into the staging directory.

## Supported Provider Layouts

### GridPane

Expected archive shape:

```text
database-*/
htdocs/wp-content/plugins/
htdocs/wp-content/themes/
htdocs/wp-content/uploads/
site-name-archived-assets/wp-config.php
site-name-archived-assets/user-configs.php
```

The database directory may contain many `*-schema.sql` and table data `.sql` files, such as mydumper-style exports.

Some GridPane exports may include `htdocs/wp-config.php`; when both locations exist, `htdocs/wp-config.php` is preferred. Otherwise, `*-archived-assets/wp-config.php` is used for config reporting and optional migration.

## SQL Combining Rules

The combined SQL file is suitable for phpMyAdmin or `wp db import`:

- All `*-schema.sql` files are written first.
- A `DROP TABLE IF EXISTS` statement is inserted before every `CREATE TABLE` statement.
- All non-schema data `.sql` files are appended after schemas.
- `CREATE DATABASE` statements are removed.
- `USE database_name` statements are removed.
- Source `FOREIGN_KEY_CHECKS` statements are removed.
- One `FOREIGN_KEY_CHECKS=0` statement is written at the top.
- One `FOREIGN_KEY_CHECKS=1` statement is written at the end.
- `SET time_zone = '+00:00';` is written using normal quoted SQL syntax.

The verifier fails the run if:

- `DROP TABLE IF EXISTS` count does not match `CREATE TABLE` count.
- Any `CREATE DATABASE` statement remains.
- Any `USE` statement remains.
- Foreign key checks are not disabled/enabled exactly once.
- An unquoted `TIME_ZONE=+00:00` style statement remains.

## File Restore Behavior

### wp-content

The importer merges these directories by default:

```text
wp-content/plugins
wp-content/themes
wp-content/uploads
```

It does not delete destination files. Existing destination symlinks are preserved unless `--replace-managed-symlinks` is passed.

The importer also skips platform-managed cache/server-helper plugins during plugin merges. These should be managed by the target platform rather than copied from the source export.

Skipped plugin slugs include:

```text
nginx-helper
redis-cache
redis-object-cache
redis-cache-pro
gridpane-redis-object-cache
wp-redis
wp-redis-cache
object-cache-pro
*redis*object*cache*
```

### Virusdie Connector Files

Root-level Virusdie files are copied automatically when detected.

Detected patterns include:

```text
vdconnect-*.php
*virusdie*
*virus-die*
*virus_die*
```

### Other Root Files

Non-core files in `htdocs/` are treated as root extras.

Examples might include:

```text
sitemap.xml
robots.txt
google*.html
custom-verification-file.html
```

Default behavior is one-by-one prompting:

```bash
--root-extras=ask
```

For automation:

```bash
--root-extras=copy
--root-extras=skip
```

### mu-plugins

`wp-content/mu-plugins` is handled separately because it can contain provider/platform-specific code.

Default behavior:

```bash
--mu-plugins=ask
```

Automation options:

```bash
--mu-plugins=copy
--mu-plugins=skip
```

Compatibility alias:

```bash
--include-mu-plugins
```

That is equivalent to:

```bash
--mu-plugins=copy
```

## wp-config.php Handling

By default, the target `wp-config.php` is not changed.

The importer writes these files into the staging directory:

```text
wp-config.diff
wp-config-extra-from-export.txt
user-configs.diff
user-configs-extra-from-export.txt
```

For GridPane exports, config files are usually extracted from the `*-archived-assets` folder:

```text
*-archived-assets/wp-config.php
*-archived-assets/user-configs.php
```

To replace the target config files with the exported config files, pass:

```bash
--migrate-config
```

The existing target config file is backed up first, and each replacement requires confirmation unless `--yes` is also passed.

## Database Import

By default, the importer asks whether to import the generated SQL into the database configured by the target `wp-config.php`. The default answer is yes:

```bash
--db-import=ask
```

For unattended imports:

```bash
--db-import=yes
```

To build the combined SQL but skip import:

```bash
--db-import=no
```

Compatibility aliases:

- `--import-db` means `--db-import=yes`.
- `--no-import-db` means `--db-import=no`.

Before import, the current DB is exported with:

```bash
wp db export
```

Skip that backup only when you already have a current DB backup:

```bash
--skip-db-backup
```

By default, the importer asks whether to clean up migration artifacts after a successful run:

```bash
--cleanup=ask
```

The cleanup prompt explicitly lists the paths that will be deleted, typically:

- The source export archive.
- The staging directory, including extracted files and generated artifacts.
- The combined SQL file when it lives outside the staging directory.

A copy of the migration report is preserved in the target root before deleting the staging directory.

For unattended cleanup:

```bash
--cleanup=yes
```

To leave all migration artifacts in place:

```bash
--cleanup=no
```

Legacy cleanup flags are still accepted as aliases for `--cleanup=yes`:

- `--delete-sql-after-import`
- `--delete-stage-after-success`
- `--delete-archive-after-success`

## Search-Replace

Run serialized-safe URL replacement after import:

```bash
--old-url=https://old.example.com \
--new-url=https://new.example.com \
--search-replace
```

The command used is:

```bash
wp search-replace OLD NEW --all-tables-with-prefix --precise --recurse-objects --skip-columns=guid
```

In `--dry-run` mode, WP-CLI search-replace is also run with `--dry-run`.

## Options

```text
--provider=auto|gridpane|legacy-mightybox|wordpress-package
                                  Export provider adapter to use. Default: auto
--target-root=PATH                WordPress document root to restore into
--stage-dir=PATH                  Staging directory. Default: target-root/restore-<archive>-<timestamp>
--db-output=PATH                  Combined SQL output path. Default: stage/<archive>-combined-phpmyadmin-import.sql
--old-url=URL                     Old URL for WP-CLI search-replace
--new-url=URL                     New URL for WP-CLI search-replace
--dry-run                         Print planned file/DB actions without changing destination files
--yes                             Answer yes to confirmation prompts
--mu-plugins=ask|copy|skip        What to do with exported mu-plugins. Default: ask
--include-mu-plugins              Alias for --mu-plugins=copy
--root-extras=ask|copy|skip       What to do with non-core root files. Default: ask
--replace-managed-symlinks        Replace destination symlink conflicts instead of preserving them
--db-import=ask|yes|no            Import combined SQL with wp db import. Default: ask, default answer yes
--target-db-method=auto|wp-cli|native
                                  Target database method. Default: auto
--import-db                       Alias for --db-import=yes
--no-import-db                    Alias for --db-import=no
--skip-db-backup                  Do not run wp db export before database import
--cleanup=ask|yes|no              Delete migration artifacts after success. Default: ask
--delete-sql-after-import         Legacy alias for --cleanup=yes
--delete-stage-after-success      Legacy alias for --cleanup=yes
--delete-archive-after-success    Legacy alias for --cleanup=yes
--search-replace                  Run wp search-replace after DB import or against current DB
--migrate-config                  After confirmation, replace target wp-config.php with exported wp-config.php
--help                            Show help
```

## Requirements

Required for basic restore:

- Bash
- `tar`
- `perl`
- `rsync`
- `awk`

Required for database backup/import:

- WP-CLI, available as `wp`, or PHP CLI plus native MariaDB/MySQL dump and client commands.

WP-CLI is specifically required for serialized-safe search-replace. If it is unavailable, the database migration succeeds and the rewrite is reported as pending.

Required on a legacy live source:

- Bash and `tar`.
- WP-CLI or PHP CLI plus `mariadb-dump`/`mysqldump`.
- `rsync` is optional; without it, catch-ups use full tar transfer.

Required for one-line remote use:

- `curl` or `wget`

## Gateway/Proxy SSH Hosts

Many MightyBox SSH sessions land on a gateway/proxy host rather than directly on the webserver container. That is supported as long as the SSH shell can access the same mounted site files and run the needed tools.

MightyBox/WP Cloud sites may also use a shared/symlinked core layout where `/srv/htdocs` contains files such as:

```text
__wp__
wp-config.php
wp-content/
wp-load.php
```

That is expected. The migrator targets `/srv/htdocs` for site files and does not require local `wp-admin` or `wp-includes` directories in the document root.

Before a restore, run:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/mightybox-io/mb-migrator/main/remote-run.sh)" -- doctor \
  --target-root=/srv/htdocs \
  --archive=/path/to/export.tar.gz
```

The doctor command checks:

- The archive is readable from the SSH shell.
- The target root exists from the SSH shell.
- `wp-content` and `wp-config.php` are visible when present.
- Shared/symlinked core markers such as `__wp__` and `wp-load.php` are visible when present.
- The target root appears writable by the current user.
- Required shell tools are available.
- WP-CLI or the native database fallback is available when DB import will be used.
- Missing WP-CLI is reported as a pending rewrite when search-replace is requested.
- WP-CLI site installation checks are skipped because the database may not be imported yet.
- Disk-space information can be read when the platform exposes it.

The one-line runner downloads itself into a temporary directory. If `/tmp` is not usable on a gateway host, set `MB_MIGRATOR_TMPDIR` to a writable location:

```bash
MB_MIGRATOR_TMPDIR=/srv/htdocs bash -c "$(curl -fsSL https://raw.githubusercontent.com/mightybox-io/mb-migrator/main/remote-run.sh)" -- doctor \
  --target-root=/srv/htdocs \
  --archive=/path/to/export.tar.gz
```

## Smoke Test

Run the included smoke test:

```bash
./tests/smoke.sh
./tests/live-smoke.sh
./tests/native-db-smoke.sh
./tests/package-smoke.sh
```

The tests cover GridPane restore compatibility, live legacy pull and catch-up behavior, portable package export/import, snapshot security, SQL normalization, and native target database backup/import.

Keep generated smoke artifacts for debugging:

```bash
KEEP_SMOKE_ARTIFACTS=1 ./tests/smoke.sh
```

## Provider Adapters

Provider-specific logic lives in `providers/`.

Current adapters:

- `gridpane.sh`
- `legacy-mightybox.sh`
- `wordpress-package.sh`

Future adapters should follow the same shape:

- Detect layout from `.archive-index.txt`.
- Load provider-specific archive path globals.
- Extract only required paths into staging.
- Leave shared DB, wp-content, wp-config, WP-CLI, and verification behavior in `lib/`.

Potential future adapters:

- Kinsta
- WP Engine
- Cloudways
- cPanel
- Generic WordPress archive

## License

MIT. See `LICENSE`.
