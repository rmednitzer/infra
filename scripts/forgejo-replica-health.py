#!/usr/bin/env python3
"""Read-only node_exporter health probe for replicated Forgejo backups."""
import datetime as dt
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

root = Path("/var/backups/forgejo-replica")
out = Path("/var/lib/node_exporter/textfile_collector/forgejo_replica.prom")
now = time.time()
valid = 0
age = -1
snapshots = sorted(p for p in root.glob("forgejo-full-*") if p.is_dir())
error = ""
try:
    assert snapshots, "No replicated Forgejo archives"
    latest = snapshots[-1]
    name = latest.name + ".tar.zst"
    archive = latest / name
    assert archive.is_file()
    assert (latest / (name + ".sha256")).is_file()
    meta = json.loads((latest / (name + ".json")).read_text())
    assert meta.get("archive") == name
    assert meta.get("sqlite_quick_check") == "ok"
    assert meta.get("service_recovered") is True
    proc = subprocess.run(["sha256sum", "-c", name + ".sha256"],
                          cwd=latest, capture_output=True, timeout=100)
    assert proc.returncode == 0, "Checksum failed"
    captured = dt.datetime.strptime(latest.name, "forgejo-full-%Y%m%dT%H%M%SZ")
    age = max(0, now - captured.replace(tzinfo=dt.timezone.utc).timestamp())
    valid = 1
except Exception as exc:
    error = str(exc)[:120]
stale = int(age < 0 or age > 9*3600 or not valid)
metrics = [
    "# TYPE forgejo_replica_age_seconds gauge",
    f"forgejo_replica_age_seconds {age:.0f}",
    "# TYPE forgejo_replica_valid gauge",
    f"forgejo_replica_valid {valid}",
    "# TYPE forgejo_replica_stale gauge",
    f"forgejo_replica_stale {stale}",
    "# TYPE forgejo_replica_snapshot_count gauge",
    f"forgejo_replica_snapshot_count {len(snapshots)}",
    "# TYPE forgejo_replica_check_timestamp_seconds gauge",
    f"forgejo_replica_check_timestamp_seconds {int(now)}",
]
drills = sorted(Path("/var/backups/forgejo-replica/restore-drills").glob("20*.txt"))
drill_age = max(0, now - drills[-1].stat().st_mtime) if drills else -1
passed = bool(drills and "result=PASS" in drills[-1].read_text())
drill_stale = int(not passed or drill_age < 0 or drill_age > 45 * 86400)
metrics.extend(["# TYPE forgejo_crosshost_restore_age_seconds gauge", f"forgejo_crosshost_restore_age_seconds {drill_age:.0f}", "# TYPE forgejo_crosshost_restore_stale gauge", f"forgejo_crosshost_restore_stale {drill_stale}"])
out.parent.mkdir(parents=True, exist_ok=True)
fd, temp = tempfile.mkstemp(prefix=".forgejo_replica.", dir=out.parent)
try:
    with os.fdopen(fd, "w") as handle:
        handle.write("\n".join(metrics) + "\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(temp, 0o644)
    os.replace(temp, out)
finally:
    if os.path.exists(temp):
        os.unlink(temp)
print(f"replica_valid={valid} stale={stale} age_seconds={age:.0f} count={len(snapshots)}")
if stale:
    subprocess.run(["logger", "-p", "daemon.err", "-t", "forgejo-replica-health",
                    "Backup replica invalid or stale: " + error],check=False)
    sys.exit(1)
