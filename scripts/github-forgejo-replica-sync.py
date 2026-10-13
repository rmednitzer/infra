#!/usr/bin/env python3
"""Replicate explicit GitHub sources with verified preservation and leased updates."""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import tempfile
import time
from urllib.parse import urlsplit


class SyncError(RuntimeError):
    pass


def atomic_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=".replica-")
    try:
        with os.fdopen(fd, "w") as handle:
            json.dump(value, handle, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(name, 0o600)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def git(args: list[str], env: dict[str, str], cwd: Path | None = None) -> str:
    process = subprocess.Popen(
        ["git", "-c", "core.hooksPath=/dev/null", *args], cwd=cwd, env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True,
    )
    try:
        output, error = process.communicate(timeout=90)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise
    if process.returncode:
        raise SyncError(error[-1200:].strip() or "Git operation failed")
    return output


def refs(text: str, managed_only: bool = True) -> dict[str, str]:
    result = {}
    for line in text.splitlines():
        sha, name = line.split(maxsplit=1)
        if name.endswith("^{}"):
            continue
        if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", sha):
            raise SyncError("Invalid Git object identifier")
        if not managed_only or name.startswith(("refs/heads/", "refs/tags/")):
            result[name] = sha
    return result


def local_refs(path: Path, env: dict[str, str], managed_only: bool = True) -> dict[str, str]:
    return refs(git(["for-each-ref", "--format=%(objectname) %(refname)"], env, path), managed_only)


def remote_refs(url: str, env: dict[str, str]) -> dict[str, str]:
    return refs(git(["ls-remote", "--heads", "--tags", url], env))


def ssh_environment(repo: dict, config: dict) -> dict[str, str]:
    # Ignore inherited SSH identities and agents: never fall back to an admin key.
    ssh = ["ssh", "-F", "/dev/null", "-i", repo["ssh_key"],
           "-p", str(config.get("ssh_port", 22)), "-o", "IdentitiesOnly=yes",
           "-o", "IdentityAgent=none", "-o", "BatchMode=yes",
           "-o", "StrictHostKeyChecking=yes", "-o", "ConnectTimeout=15",
           "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2",
           "-o", "UserKnownHostsFile=" + config["known_hosts"]]
    return dict(os.environ, GIT_TERMINAL_PROMPT="0", GIT_CONFIG_GLOBAL="/dev/null",
                GIT_CONFIG_NOSYSTEM="1", GIT_SSH_COMMAND=shlex.join(ssh))


def validate_config(config: dict) -> None:
    if config.get("schema_version") != 1 or config.get("authoritative") is not True:
        raise SyncError("Explicit schema_version=1 and authoritative=true are required")
    if not config.get("repositories"):
        raise SyncError("Repository allowlist must not be empty")
    names, keys, destinations = set(), set(), set()
    for repo in config["repositories"]:
        name = repo.get("name", "")
        if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]*", name) or name in names:
            raise SyncError("Unsafe or duplicate repository name")
        names.add(name)
        source = urlsplit(repo.get("source", ""))
        if (source.scheme != "https" or source.hostname != "github.com"
                or source.username or source.password or source.query or source.fragment
                or not re.fullmatch(r"/[A-Za-z0-9_.-]+/" + re.escape(name) + r"\.git", source.path)):
            raise SyncError("Source must be an explicit public GitHub repository")
        destination = repo.get("destination", "")
        if not re.fullmatch(r"git@[A-Za-z0-9_.-]+:[A-Za-z0-9_.-]+/" + re.escape(name) + r"\.git", destination):
            raise SyncError("Destination must identify the matching Forgejo repository")
        if destination in destinations:
            raise SyncError("Duplicate destination")
        destinations.add(destination)
        key = repo.get("ssh_key", "")
        if not Path(key).is_absolute() or key in keys:
            raise SyncError("Each repository needs its own absolute SSH key path")
        keys.add(key)
    for key in ("state_dir", "known_hosts", "metrics_file"):
        if not Path(config.get(key, "")).is_absolute():
            raise SyncError(f"{key} must be an absolute path")


def preserve(destination: str, observed: dict[str, str], env: dict[str, str],
             work: Path, bundle: Path) -> dict:
    snapshot = work / "before.git"
    git(["clone", "--mirror", destination, str(snapshot)], env)
    captured = local_refs(snapshot, env)
    if captured != observed:
        raise SyncError("Destination changed while creating preservation snapshot")
    all_refs = local_refs(snapshot, env, False)
    if not all_refs:
        return {"empty_destination": True, "refs": {}, "verified": True}
    bundle.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    git(["bundle", "create", str(bundle), "--all"], env, snapshot)
    os.chmod(bundle, 0o600)
    restored = work / "restore.git"
    git(["init", "--bare", str(restored)], env)
    git(["bundle", "verify", str(bundle)], env, restored)
    git(["fetch", str(bundle), "refs/*:refs/*"], env, restored)
    git(["fsck", "--full"], env, restored)
    if local_refs(restored, env, False) != all_refs:
        raise SyncError("Preservation bundle failed exact ref restoration")
    with bundle.open("rb") as handle:
        digest = hashlib.file_digest(handle, "sha256").hexdigest()
    return {"bundle": str(bundle), "sha256": digest,
            "refs": all_refs, "verified": True}


def sync_repo(repo: dict, config: dict, run_id: str, env: dict[str, str] | None = None) -> dict:
    env = env or ssh_environment(repo, config)
    state = Path(config["state_dir"])
    stage = state / "source" / (repo["name"] + ".git")
    stage.parent.mkdir(parents=True, exist_ok=True)
    if not stage.exists():
        git(["init", "--bare", str(stage)], env)
    git(["fetch", "--prune", "--no-tags", repo["source"],
         "+refs/heads/*:refs/heads/*", "+refs/tags/*:refs/tags/*"], env, stage)
    desired = local_refs(stage, env)
    if "refs/heads/main" not in desired:
        raise SyncError("Source main is absent; refusing destination changes")
    observed = remote_refs(repo["destination"], env)
    changed = sorted(ref for ref in desired.keys() | observed.keys()
                     if desired.get(ref) != observed.get(ref))
    if not changed:
        return {"success": True, "changed_refs": [], "main_sha": desired["refs/heads/main"]}
    if shutil.disk_usage(state).free < config.get("min_free_bytes", 1024 ** 3):
        raise SyncError("Insufficient free space for preservation; no refs changed")
    work_parent = state / "work"
    work_parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=repo["name"] + "-", dir=work_parent) as directory:
        bundle = state / "recovery" / run_id / (repo["name"] + ".bundle")
        preserved = preserve(repo["destination"], observed, env, Path(directory), bundle)
        receipt = {"repository": repo["name"], "before": observed, "desired": desired,
                   "preservation": preserved, "changed_refs": changed, "push_submitted": False}
        receipt_path = state / "recovery" / run_id / (repo["name"] + ".json")
        atomic_json(receipt_path, receipt)
        # Every update and deletion is leased to the captured destination SHA.
        leases = [f"--force-with-lease={ref}:{observed.get(ref, '')}" for ref in changed]
        updates = [f"{desired.get(ref, '')}:{ref}" for ref in changed]
        receipt["push_submitted"] = True
        atomic_json(receipt_path, receipt)
        push_error = None
        try:
            git(["push", "--atomic", *leases, repo["destination"], *updates], env, stage)
        except (SyncError, subprocess.TimeoutExpired) as exc:
            # An interrupted push is not retried. Reconcile the remote outcome.
            push_error = str(exc)
        resulting = remote_refs(repo["destination"], env)
        receipt["after"] = resulting
        receipt["success"] = resulting == desired
        receipt["push_error"] = push_error
        atomic_json(receipt_path, receipt)
        if resulting != desired:
            raise SyncError(push_error or "Post-push refs do not match the captured source")
        return {"success": True, "changed_refs": changed, "main_sha": desired["refs/heads/main"],
                "preservation": preserved, "reconciled_push_error": bool(push_error)}


def write_metrics(config: dict, status: dict) -> None:
    expected = {repo["name"] for repo in config["repositories"]}
    if set(status["repositories"]) != expected:
        raise SyncError("Metric receipt does not cover the configured repository set")
    for key in ("attempt_timestamp", "last_success_timestamp"):
        if type(status[key]) is not int or not 0 <= status[key] <= time.time() + 60:
            raise SyncError("Invalid metric timestamp")
    if type(status["success"]) is not bool or any(
        type(result["success"]) is not bool for result in status["repositories"].values()
    ):
        raise SyncError("Invalid metric result")
    lines = ["# TYPE github_forgejo_replica_sync_success gauge",
             f"github_forgejo_replica_sync_success {int(status['success'])}",
             "# TYPE github_forgejo_replica_sync_timestamp_seconds gauge",
             f"github_forgejo_replica_sync_timestamp_seconds {status['attempt_timestamp']}",
             "# TYPE github_forgejo_replica_last_success_timestamp_seconds gauge",
             f"github_forgejo_replica_last_success_timestamp_seconds {status['last_success_timestamp']}",
             "# TYPE github_forgejo_replica_repository_success gauge"]
    for name, result in status["repositories"].items():
        lines.append(f'github_forgejo_replica_repository_success{{repo="{name}"}} {int(result["success"])}')
    path = Path(config["metrics_file"])
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=".github-forgejo-")
    try:
        with os.fdopen(fd, "w") as handle:
            handle.write("\n".join(lines) + "\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(name, 0o644)
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default="/etc/github-forgejo-replica/config.json")
    parser.add_argument("--check-config", action="store_true")
    parser.add_argument("--metrics-only", action="store_true")
    args = parser.parse_args()
    os.umask(0o077)
    config = json.loads(Path(args.config).read_text())
    validate_config(config)
    if args.check_config:
        print(f"Validated {len(config['repositories'])} explicitly scoped repositories")
        return 0
    if args.metrics_only:
        status = json.loads((Path(config["state_dir"]) / "latest.json").read_text())
        if os.environ.get("SERVICE_RESULT", "success") != "success":
            status["success"] = False
        write_metrics(config, status)
        return 0
    state = Path(config["state_dir"])
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    with (state / "sync.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            print("Another replica sync owns the lock; no work submitted")
            return 75
        previous = state / "latest.json"
        old = json.loads(previous.read_text()) if previous.exists() else {}
        now = int(time.time())
        run_id = time.strftime("%Y%m%dT%H%M%SZ", time.gmtime()) + f"-{os.getpid()}"
        status = {"run_id": run_id, "attempt_timestamp": now,
                  "last_success_timestamp": old.get("last_success_timestamp", 0),
                  "success": False, "repositories": {
                      repo["name"]: {"success": False, "error": "not attempted"}
                      for repo in config["repositories"]}}
        atomic_json(previous, status)
        for repo in config["repositories"]:
            try:
                result = sync_repo(repo, config, run_id)
            except Exception as exc:
                result = {"success": False, "error": str(exc)[-1200:]}
            status["repositories"][repo["name"]] = result
            print(f"{repo['name']}: {'verified' if result['success'] else 'FAILED'}", flush=True)
            atomic_json(previous, status)
        status["success"] = all(r["success"] for r in status["repositories"].values())
        if status["success"]:
            status["last_success_timestamp"] = int(time.time())
        atomic_json(previous, status)
        return 0 if status["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
