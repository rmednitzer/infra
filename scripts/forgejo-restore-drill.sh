#!/usr/bin/env bash
set -euo pipefail
umask 077
backup=$(find /var/backups/forgejo -maxdepth 1 -type f -name "forgejo-full-*.tar.zst" | LC_ALL=C sort | tail -1)
test -n "$backup"
receipt=/var/backups/forgejo/restore-drills
port=31389
unit=forgejo-restore-drill
tmp=$(mktemp -d /var/tmp/forgejo-isolated-restore.XXXXXXXX)
if ss -ltn | grep -q "127.0.0.1:$port "; then
  echo "Refusing drill: isolated loopback port already allocated" >&2
  exit 3
fi
clean() {
  systemctl stop "$unit.service" >/dev/null 2>&1 || :
  for i in $(seq 1 15); do
    if ! systemctl is-active --quiet "$unit.service"; then break; fi
    sleep 1
  done
  if systemctl is-active --quiet "$unit.service"; then
    echo "ERROR: drill service still active; retained $tmp" >&2
    return 1
  fi
  rm -rf -- "$tmp"
}
trap clean EXIT
cd /var/backups/forgejo
sha256sum -c "$(basename "$backup").sha256"
tar -I zstd -xf "$backup" -C "$tmp" var/lib/forgejo etc/forgejo
test -s "$tmp/var/lib/forgejo/data/forgejo.db"
test -s "$tmp/etc/forgejo/app.ini"
chown -R git:git "$tmp/var/lib/forgejo" "$tmp/etc/forgejo"
chmod 0755 "$tmp" "$tmp/var" "$tmp/var/lib" "$tmp/etc"
python3 - "$tmp" "$port" <<'PY'
from pathlib import Path
import sys
t=Path(sys.argv[1]); port=sys.argv[2]
p=t/'etc/forgejo/app.ini'
raw=p.read_text()
raw=raw.replace('/var/lib/forgejo',str(t/'var/lib/forgejo'))
raw=raw.replace('/etc/forgejo',str(t/'etc/forgejo'))
raw=raw.replace('/home/git',str(t/'home/git'))
blocks={'server':{'HTTP_ADDR':'127.0.0.1','HTTP_PORT':port,'DOMAIN':'localhost','ROOT_URL':f'http://127.0.0.1:{port}/','DISABLE_SSH':'true','START_SSH_SERVER':'false','OFFLINE_MODE':'true'},
        'service':{'ENABLE_NOTIFY_MAIL':'false'},'mailer':{'ENABLED':'false'},'actions':{'ENABLED':'false'}}
section='';seen=set();output=[]
def flush(sec):
  for key,value in blocks.get(sec,{}).items():
    if (sec,key) not in seen:output.append(f'{key} = {value}')
for line in raw.splitlines():
  s=line.strip()
  if s.startswith('[') and s.endswith(']'):
    flush(section)
    section=s[1:-1].lower()
  if '=' in s and not s.startswith(('#',';')):
    key=s.split('=',1)[0].strip().upper()
    if key in blocks.get(section,{}):
      output.append(f'{key} = {blocks[section][key]}')
      seen.add((section,key))
      continue
  output.append(line)
flush(section)
for sec,keys in blocks.items():
  if f'[{sec}]' not in raw.lower():
    output.append(f'[{sec}]')
    output.extend(f'{key} = {value}' for key,value in keys.items())
p.write_text('\n'.join(output)+'\n')
PY
chown git:git "$tmp/etc/forgejo/app.ini"
db="$tmp/var/lib/forgejo/data/forgejo.db"
test "$(sqlite3 -readonly "$db" 'PRAGMA integrity_check;')" = ok
expected=$(sqlite3 -readonly "$db" "SELECT count(*) FROM repository;")
git --git-dir="$tmp/var/lib/forgejo/data/forgejo-repositories/lab/relay-shell.git" fsck --full --no-reflogs --no-progress >/dev/null 2>&1
systemd-run --unit="$unit" --collect \
  -p User=git -p Group=git \
  -p WorkingDirectory="$tmp/var/lib/forgejo" \
  -p "Environment=FORGEJO_WORK_DIR=$tmp/var/lib/forgejo" \
  -p "Environment=GITEA_WORK_DIR=$tmp/var/lib/forgejo" \
  -p Environment=HOME=/var/lib/forgejo \
  -p IPAddressDeny=any -p IPAddressAllow=localhost \
  -p NoNewPrivileges=yes -p PrivateDevices=yes \
  -p ProtectSystem=strict -p "ReadWritePaths=$tmp" \
  /usr/local/bin/forgejo web --config "$tmp/etc/forgejo/app.ini" \
  --work-path "$tmp/var/lib/forgejo" --port "$port" \
  --pid "$tmp/var/lib/forgejo/forgejo.pid" --quiet >/dev/null
healthy=no
for i in $(seq 1 35); do
  if curl -sS --noproxy '*' --connect-timeout 1 --max-time 3 "http://127.0.0.1:$port/api/v1/version" > "$tmp/api-version.json" 2>/dev/null; then
    healthy=yes; break
  fi
  if ! systemctl is-active --quiet "$unit.service"; then break; fi
  sleep 1
done
if [[ "$healthy" != yes ]]; then
  echo 'ERROR: isolated Forgejo failed to respond' >&2
  printf 'service_state='; systemctl is-active "$unit.service" || :
  ss -ltn | grep ':31389 ' || :
  curl -sS --noproxy '*' --max-time 3 "http://127.0.0.1:$port/api/v1/version" | head -c 220 || :
  echo
  curl -sS --noproxy '*' -o /dev/null -w 'login_http=%{http_code}\n' --max-time 3 "http://127.0.0.1:$port/user/login" || :
  curl -sS --noproxy '*' -o /dev/null -w 'root_http=%{http_code}\n' --max-time 3 "http://127.0.0.1:$port/" || :
  find "$tmp/var/lib/forgejo/log" -maxdepth 1 -type f -name '*.log' -printf '%f\n' 2>/dev/null | head -8
  for p in "$tmp/var/lib/forgejo/log/gitea.log" "$tmp/var/lib/forgejo/log/forgejo.log"; do
    if test -f "$p"; then tail -15 "$p" | grep -Ei 'listen|start|error|warn|database|http|initialized|server' | tail -10 || :; fi
  done
  journalctl -u "$unit.service" -n 12 --no-pager --output=cat | sed -E 's/([Pp]assword|SECRET_KEY|INTERNAL_TOKEN)=.*/\1=[REDACTED]/'
  exit 1
fi
python3 - "$tmp/api-version.json" <<'PY'
import json,sys
v=json.load(open(sys.argv[1]))
assert v.get('version') or v.get('message') == 'Only signed in user is allowed to call APIs.',v
print('Restored API access control:', v.get('version') or v.get('message'))
PY
login=$(curl -sS --noproxy '*' -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:$port/user/login")
test "$login" = 200
actual=$(sqlite3 -readonly "$db" 'select count(*) from repository;')
test "$actual" = "$expected" && test "$actual" -ge 20
mkdir -p "$receipt"
stamp=$(date -u +%Y%m%dT%H%M%SZ)
{
  echo "time_utc=$stamp"
  echo "backup=$(basename "$backup")"
  echo 'backup_sha256=verified'
  echo 'sqlite_integrity=ok'
  echo 'unauthenticated_api=access_control_enforced'
  echo "repository_count=$actual"
  echo "http_login=$login"
  echo 'isolated_network=localhost_only'
  echo 'production_service_touched=no'
  echo 'result=PASS'
} > "$receipt/$stamp.txt"
echo "PASS: restored Forgejo served UI and API, repositories=$actual"
