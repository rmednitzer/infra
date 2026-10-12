#!/usr/bin/env python3
"""Read-only backup integrity/freshness probe for node_exporter textfile metrics."""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

UTC = dt.timezone.utc
parser = argparse.ArgumentParser()
parser.add_argument("kind", choices=("github", "forgejo"))
args = parser.parse_args()
if args.kind == "github":
    root = Path("/var/backups/github-recovery")
    out = Path("/var/lib/node_exporter/textfile_collector/github_recovery.prom")
    max_age = 36 * 3600
else:
    root = Path("/var/backups/forgejo")
    out = Path("/var/lib/node-exporter/textfile/forgejo_backup.prom")
    max_age = 9 * 3600
now = time.time()
age = -1.0
valid = 0
snapshots = []
description = ""
try:
    if args.kind == "github":
        snapshots = sorted(p for p in root.glob("20??????T??????Z") if p.is_dir())
        assert snapshots, "no GitHub snapshots"
        latest = snapshots[-1]
        stamp = dt.datetime.strptime(latest.name, "%Y%m%dT%H%M%SZ").replace(tzinfo=UTC).timestamp()
        age = max(0.0, now-stamp)
        meta = json.loads((latest/"manifest.json").read_text())
        assert len(meta["repositories"]) == 8
        for entry in meta["repositories"]:
            assert (latest/(entry["name"]+".bundle")).is_file()
        proc = subprocess.run(["sha256sum", "-c", "SHA256SUMS"], cwd=latest,
                              stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=70)
        assert proc.returncode == 0, "SHA256 verification failed"
        valid = 1
    else:
        snapshots = sorted(root.glob("forgejo-full-*.tar.zst"))
        assert snapshots, "no Forgejo snapshots"
        latest = snapshots[-1]
        stamp = latest.stat().st_mtime
        age = max(0.0, now-stamp)
        for extension in (".sha256",".json"):
            assert Path(str(latest)+extension).is_file()
        proc = subprocess.run(["sha256sum","-c", latest.name+".sha256"], cwd=root,
                              stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, timeout=70)
        assert proc.returncode == 0, "SHA256 verification failed"
        state = Path("/var/lib/forgejo-backup/last-success")
        assert state.is_file(), "no last-success receipt"
        valid = 1
except Exception as exc:
    description = str(exc)[:140].replace("\n"," ")
stale = int(age < 0 or age > max_age or not valid)
prefix = "github_recovery" if args.kind == "github" else "forgejo_backup"
metrics = [
    f"# HELP {prefix}_age_seconds Seconds since most recent snapshot.",
    f"# TYPE {prefix}_age_seconds gauge",
    f"{prefix}_age_seconds {age:.0f}",
    f"# HELP {prefix}_valid Latest backup checksum and metadata verified.",
    f"# TYPE {prefix}_valid gauge",
    f"{prefix}_valid {valid}",
    f"# HELP {prefix}_stale Backup age, availability or integrity threshold exceeded.",
    f"# TYPE {prefix}_stale gauge",
    f"{prefix}_stale {stale}",
    f"# TYPE {prefix}_snapshot_count gauge",
    f"{prefix}_snapshot_count {len(snapshots)}",
    f"# TYPE {prefix}_check_timestamp_seconds gauge",
    f"{prefix}_check_timestamp_seconds {int(now)}",
]
if args.kind == "forgejo":
    drills = sorted(Path("/var/backups/forgejo/restore-drills").glob("20*.txt"))
    drill_age = -1
    if drills:
        try:
            d = dt.datetime.strptime(drills[-1].stem,"%Y%m%dT%H%M%SZ").replace(tzinfo=UTC).timestamp()
            drill_age = max(0,now-d)
        except ValueError:
            pass
    metrics += [
        "# TYPE forgejo_restore_drill_age_seconds gauge",
        f"forgejo_restore_drill_age_seconds {drill_age:.0f}",
        "# TYPE forgejo_restore_drill_stale gauge",
        f"forgejo_restore_drill_stale {int(drill_age<0 or drill_age>45*86400)}",
    ]
out.parent.mkdir(parents=True,exist_ok=True)
fd,path=tempfile.mkstemp(prefix="."+out.name+".",dir=out.parent)
try:
    with os.fdopen(fd,"w") as f:
        f.write("\n".join(metrics)+"\n")
        f.flush()
        os.fsync(f.fileno())
    os.chmod(path,0o644)
    os.replace(path,out)
finally:
    if os.path.exists(path):os.unlink(path)
print(f"{args.kind}: integrity={valid}, stale={stale}, age={age:.0f}s, snapshots={len(snapshots)}")
if stale:
    sys.stderr.write(f"BACKUP_ALERT {args.kind}: {description or 'stale or invalid backup'}\n")
    sys.exit(1)
