#!/bin/sh
set -eu

if [ -z "${MB_MIGRATOR_DESTINATION_PASSWORD:-}" ]; then
  exit 1
fi

printf '%s\n' "$MB_MIGRATOR_DESTINATION_PASSWORD"
