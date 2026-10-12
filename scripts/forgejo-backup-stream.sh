#!/usr/bin/env bash
set -euo pipefail
umask 077
cd /var/backups/forgejo
latest=$(find . -maxdepth 1 -type f -name 'forgejo-full-*.tar.zst' -printf '%f\n' | LC_ALL=C sort | tail -n1)
[[ "$latest" =~ ^forgejo-full-[0-9]{8}T[0-9]{6}Z\.tar\.zst$ ]] || exit 11
test -f "$latest.sha256" && test -f "$latest.json"
# Never replicate corrupt or obsolete backup sets.
sha256sum -c "$latest.sha256" >/dev/null
now=$(date +%s)
age=$((now - $(stat -c %Y "$latest")))
(( age >= 0 && age <= 12*3600 )) || exit 12
# Only these three prevalidated files are emitted; no caller-controlled paths.
tar -cf - -- "$latest" "$latest.sha256" "$latest.json"
