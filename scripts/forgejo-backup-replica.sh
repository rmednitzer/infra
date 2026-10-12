#!/usr/bin/env bash
set -euo pipefail
umask 077
base=/var/backups/forgejo-replica
# The root-owned local file holds host-specific connection parameters.
# Keep network locators and private key paths out of public repositories.
source /etc/forgejo-replica.env
key="$FORGEJO_BACKUP_KEY"
known_hosts="$FORGEJO_BACKUP_KNOWN_HOSTS"
test -s "$key" && test -s "$known_hosts"
mkdir -p "$base"
chmod 0700 "$base"
stage=$(mktemp -d "$base/.stage.XXXXXXXX")
cleanup() { test ! -d "$stage" || rm -rf -- "$stage"; }
trap cleanup EXIT
timeout 300 ssh -i "$key" -o IdentitiesOnly=yes -o BatchMode=yes \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$known_hosts" \
    -o ConnectTimeout=8 -o ClearAllForwardings=yes \
    -o ForwardAgent=no -T "$FORGEJO_BACKUP_SOURCE" |
    tar -xf - -C "$stage"
archive=$(find "$stage" -maxdepth 1 -type f -name 'forgejo-full-*.tar.zst' -printf '%f\n')
test "$(printf '%s\n' "$archive" | wc -l)" -eq 1
[[ "$archive" =~ ^forgejo-full-[0-9]{8}T[0-9]{6}Z\.tar\.zst$ ]]
test -f "$stage/$archive.sha256"
test -f "$stage/$archive.json"
test "$(find "$stage" -maxdepth 1 -type f | wc -l)" -eq 3
(cd "$stage" && sha256sum -c "$archive.sha256" >/dev/null)
zstd -tq "$stage/$archive"
python3 - "$stage/$archive.json" "$archive" <<'PY'
import json,sys
meta=json.load(open(sys.argv[1]))
assert meta.get('archive')==sys.argv[2]
assert meta.get('sqlite_quick_check')=='ok'
assert meta.get('service_recovered') is True
PY
name=$(basename "$archive" .tar.zst)
dest="$base/$name"
if [[ -e "$dest" ]]; then
  if cmp -s "$stage/$archive.sha256" "$dest/$archive.sha256"; then
    echo "Already verified and present: $name"
    exit 0
  fi
  echo "ERROR: immutable archive-name collision" >&2
  exit 15
fi
chmod 0600 "$stage"/*
mv -T "$stage" "$dest"
trap - EXIT
echo "VERIFIED replication: $dest"
# Retain up to 28 source generations; never prune after a failed transfer.
find "$base" -mindepth 1 -maxdepth 1 -type d -name 'forgejo-full-*' -printf '%f\n' |
    LC_ALL=C sort -r | tail -n +29 | while read -r old; do
  [[ "$old" =~ ^forgejo-full-[0-9]{8}T[0-9]{6}Z$ ]] || exit 16
  rm -rf -- "$base/$old"
done
