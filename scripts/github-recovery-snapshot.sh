#!/usr/bin/env bash
set -euo pipefail
umask 077
export GIT_TERMINAL_PROMPT=0
BASE=/var/backups/github-recovery
mkdir -p "$BASE"
chmod 0700 "$BASE"
STAMP=$(date -u +%Y%m%dT%H%M%SZ)
STAGE=$(mktemp -d "$BASE/.stage.XXXXXXXX")
trap 'if [[ -d "$STAGE" ]]; then rm -rf -- "$STAGE"; fi' EXIT
printf 'name\tmain_sha\tbranch_refs\ttag_refs\n' > "$STAGE/repositories.tsv"
repos=(automation core-graph relay-shell infra agents 6dof-ascent-sim rmednitzer.github.io runbooks)
for repo in "${repos[@]}"; do
  url="https://github.com/rmednitzer/${repo}.git"
  echo "snapshot: ${repo}"
  git -c protocol.version=2 clone --mirror --quiet "$url" "$STAGE/${repo}.git"
  git --git-dir="$STAGE/${repo}.git" fsck --full --no-reflogs --no-progress >/dev/null
  git --git-dir="$STAGE/${repo}.git" bundle create "$STAGE/${repo}.bundle" --all >/dev/null
  git --git-dir="$STAGE/${repo}.git" bundle verify "$STAGE/${repo}.bundle" >/dev/null 2>&1
  main=$(git --git-dir="$STAGE/${repo}.git" rev-parse refs/heads/main)
  observed=$(git ls-remote "$url" refs/heads/main | awk '{print $1}')
  if [[ "$main" != "$observed" || -z "$main" ]]; then
    echo "ERROR: ${repo} main changed during capture or is missing" >&2
    exit 2
  fi
  branches=$(git --git-dir="$STAGE/${repo}.git" for-each-ref refs/heads --format='%(refname)' | wc -l)
  tags=$(git --git-dir="$STAGE/${repo}.git" for-each-ref refs/tags --format='%(refname)' | wc -l)
  printf '%s\t%s\t%s\t%s\n' "$repo" "$main" "$branches" "$tags" >> "$STAGE/repositories.tsv"
  rm -rf -- "$STAGE/${repo}.git"
done
(cd "$STAGE" && sha256sum -- *.bundle > SHA256SUMS && sha256sum -c SHA256SUMS >/dev/null)
python3 - "$STAGE" "$STAMP" <<'PY'
import csv, json, pathlib, sys
p=pathlib.Path(sys.argv[1])
rows=list(csv.DictReader((p/'repositories.tsv').open(), delimiter='\t'))
assert len(rows)==8
(p/'manifest.json').write_text(json.dumps({'schema_version':1,'captured_utc':sys.argv[2],'source':'github.com/rmednitzer','scope':'Git branches and tags, no Git LFS, PR metadata, releases or GitHub Actions artifacts','repositories':rows},indent=2)+'\n')
PY
mv -T -- "$STAGE" "$BASE/$STAMP"
trap - EXIT
printf 'VERIFIED GitHub recovery snapshot %s (8 bundles)\n' "$BASE/$STAMP"
