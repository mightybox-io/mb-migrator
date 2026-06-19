# MB Migrator

`mb-migrator` restores WordPress provider exports into a MightyBox-style WordPress document root.

It is built for migration work where a single provider export archive contains site files plus split SQL database dumps. The first supported provider adapter is GridPane-style SFTP exports. The project is intentionally modular so support for other providers can be added behind provider adapters.

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
--provider=auto|gridpane          Export provider adapter to use. Default: auto
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

Required for DB import and search-replace:

- WP-CLI, available as `wp`

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
- WP-CLI is available when DB import or search-replace will be used.
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
```

It builds a small GridPane-style fixture archive, restores it into a disposable target, verifies file copies, verifies SQL safety rules, and cleans up generated artifacts.

Keep generated smoke artifacts for debugging:

```bash
KEEP_SMOKE_ARTIFACTS=1 ./tests/smoke.sh
```

## Provider Adapters

Provider-specific logic lives in `providers/`.

Current adapter:

- `gridpane.sh`

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
