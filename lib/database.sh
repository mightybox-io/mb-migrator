#!/usr/bin/env bash

combine_database_sql() {
  local db_dir="$1"
  local outfile="$2"

  [[ -d "$db_dir" ]] || die "Database directory not found: $db_dir"

  log "Combining database SQL files"
  perl - "$db_dir" "$outfile" <<'PERL'
use strict;
use warnings;

my ($db_dir, $outfile) = @ARGV;
opendir(my $dh, $db_dir) or die "Cannot open $db_dir: $!\n";
my @sql = sort grep { /\.sql\z/ && -f "$db_dir/$_" } readdir($dh);
closedir($dh);

my @schema = grep { /-schema\.sql\z/ } @sql;
my @data = grep { !/-schema\.sql\z/ && !/-schema-create\.sql\z/ } @sql;

open(my $out, ">", $outfile) or die "Cannot write $outfile: $!\n";
binmode($out);
print $out "-- Combined phpMyAdmin/WP-CLI import generated from split SQL files\n";
print $out "-- Source folder: $db_dir\n";
print $out "/*!40101 SET NAMES binary*/;\n";
print $out "/*!40014 SET FOREIGN_KEY_CHECKS=0*/;\n";
print $out "SET time_zone = '+00:00';\n\n";

my %stats = (
  removed_create_database => 0,
  removed_use => 0,
  removed_source_fk => 0,
  removed_source_drop => 0,
  drops_inserted => 0,
  creates_seen => 0,
);

sub append_file {
  my ($name, $is_schema) = @_;
  my $path = "$db_dir/$name";
  print $out "-- Begin $name\n";
  open(my $in, "<", $path) or die "Cannot read $path: $!\n";
  binmode($in);
  while (my $line = <$in>) {
    if ($line =~ /^\s*CREATE\s+DATABASE\b/i) {
      $stats{removed_create_database}++;
      next;
    }
    if ($line =~ /^\s*USE\s+/i) {
      $stats{removed_use}++;
      next;
    }
    if ($line =~ /^\s*(?:\/\*!\d+\s*)?SET\s+FOREIGN_KEY_CHECKS\s*=/i) {
      $stats{removed_source_fk}++;
      next;
    }
    if ($line =~ /^\s*DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?/i) {
      $stats{removed_source_drop}++;
      next;
    }
    if ($line =~ /^\s*CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?((?:`[^`]+`\.)?`[^`]+`|[^\s(]+)/i) {
      $stats{creates_seen}++;
      if ($is_schema) {
        print $out "DROP TABLE IF EXISTS $1;\n";
        $stats{drops_inserted}++;
      }
    }
    print $out $line;
    print $out "\n" if $line ne "" && $line !~ /[\r\n]\z/;
  }
  close($in);
  print $out "-- End $name\n\n";
}

append_file($_, 1) for @schema;
my $single_file_dump = scalar(@schema) == 0 && scalar(@data) == 1;
append_file($_, $single_file_dump ? 1 : 0) for @data;
print $out "/*!40014 SET FOREIGN_KEY_CHECKS=1*/;\n";
close($out);

print "schema_files=" . scalar(@schema) . "\n";
print "data_files=" . scalar(@data) . "\n";
print "removed_create_database_lines=$stats{removed_create_database}\n";
print "removed_use_lines=$stats{removed_use}\n";
print "removed_source_fk_lines=$stats{removed_source_fk}\n";
print "removed_source_drop_lines=$stats{removed_source_drop}\n";
PERL
}

verify_database_sql() {
  local outfile="$1"
  [[ -f "$outfile" ]] || die "Combined SQL not found: $outfile"

  log "Verifying combined SQL"
  local output
  output="$(perl -ne '
    $bad_tz++ if /TIME_ZONE\s*=\s*\+\d\d:\d\d/i;
    $create++ if /^\s*CREATE\s+TABLE\b/i;
    $drop++ if /^\s*DROP\s+TABLE\s+IF\s+EXISTS\b/i;
    $createdb++ if /^\s*CREATE\s+DATABASE\b/i;
    $use++ if /^\s*USE\s+/i;
    $fk0++ if /FOREIGN_KEY_CHECKS\s*=\s*0/i;
    $fk1++ if /FOREIGN_KEY_CHECKS\s*=\s*1/i;
    END {
      print "bad_unquoted_timezone=" . ($bad_tz||0) . "\n";
      print "create_tables=" . ($create||0) . "\n";
      print "drop_tables=" . ($drop||0) . "\n";
      print "create_database_statements=" . ($createdb||0) . "\n";
      print "use_statements=" . ($use||0) . "\n";
      print "foreign_key_disable_statements=" . ($fk0||0) . "\n";
      print "foreign_key_enable_statements=" . ($fk1||0) . "\n";
    }
  ' "$outfile")"
  printf '%s\n' "$output"
  report "SQL verification:"
  printf '%s\n' "$output" >> "$REPORT_FILE"

  local create drop createdb use fk0 fk1 bad_tz
  create="$(printf '%s\n' "$output" | awk -F= '/^create_tables=/{print $2}')"
  drop="$(printf '%s\n' "$output" | awk -F= '/^drop_tables=/{print $2}')"
  createdb="$(printf '%s\n' "$output" | awk -F= '/^create_database_statements=/{print $2}')"
  use="$(printf '%s\n' "$output" | awk -F= '/^use_statements=/{print $2}')"
  fk0="$(printf '%s\n' "$output" | awk -F= '/^foreign_key_disable_statements=/{print $2}')"
  fk1="$(printf '%s\n' "$output" | awk -F= '/^foreign_key_enable_statements=/{print $2}')"
  bad_tz="$(printf '%s\n' "$output" | awk -F= '/^bad_unquoted_timezone=/{print $2}')"

  [[ "$create" == "$drop" ]] || die "DROP/CREATE mismatch: $drop drops vs $create creates"
  [[ "$createdb" == "0" ]] || die "CREATE DATABASE remains in output"
  [[ "$use" == "0" ]] || die "USE statement remains in output"
  [[ "$fk0" == "1" && "$fk1" == "1" ]] || die "Unexpected FK check counts: disable=$fk0 enable=$fk1"
  [[ "$bad_tz" == "0" ]] || die "Unquoted TIME_ZONE statement remains in output"
}
