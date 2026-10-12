#!/usr/bin/env python3
"""Read-only GitHub/Forgejo main-reference comparison. Never fetches or changes refs."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

repos = ("automation","core-graph","relay-shell","infra","agents",
        "6dof-ascent-sim","rmednitzer.github.io","runbooks")
root = Path("/var/lib/forgejo/data/forgejo-repositories/lab")
out = Path("/var/lib/node-exporter/textfile/forgejo_upstream_refs.prom")
environment = dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_CONFIG_GLOBAL="/dev/null")
lines = [
    "# HELP forgejo_upstream_main_match Whether independent Forgejo and GitHub main SHAs match.",
    "# TYPE forgejo_upstream_main_match gauge",
]
probes = 0
matching = 0
for repo in repos:
    location = root / (repo+".git")
    local = subprocess.run(["git","--git-dir="+str(location),"rev-parse","refs/heads/main"],
                            text=True,capture_output=True,timeout=10,env=environment)
    remote = subprocess.run(["git","ls-remote",f"https://github.com/rmednitzer/{repo}.git",
                            "refs/heads/main"],
                            text=True,capture_output=True,timeout=20,env=environment)
    valid = local.returncode==0 and remote.returncode==0 and len(remote.stdout.split())==2
    equal = int(valid and local.stdout.strip() == remote.stdout.split()[0])
    probes += int(valid)
    matching += equal
    lines.append(f'forgejo_upstream_main_match{{repo="{repo}"}} {equal}')
lines += [
    "# TYPE forgejo_upstream_main_match_count gauge",
    f"forgejo_upstream_main_match_count {matching}",
    "# TYPE forgejo_upstream_probe_success gauge",
    f"forgejo_upstream_probe_success {int(probes==len(repos))}",
    "# TYPE forgejo_upstream_ref_check_timestamp_seconds gauge",
    f"forgejo_upstream_ref_check_timestamp_seconds {int(time.time())}",
]
fd,name = tempfile.mkstemp(prefix=".forgejo_upstream.",dir=out.parent)
try:
    with os.fdopen(fd,"w") as handle:
        handle.write("\n".join(lines)+"\n")
        handle.flush()
        os.fsync(handle.fileno())
    os.chmod(name,0o644)
    os.replace(name,out)
finally:
    if os.path.exists(name):
        os.unlink(name)
print(f"Independent Forgejo refs matching GitHub: {matching}/{len(repos)}; probes={probes}")
if probes != len(repos):
    sys.exit(1)
