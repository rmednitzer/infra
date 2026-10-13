"""Disposable Git repositories exercise preservation, pruning, leases and failure paths."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).parents[1] / "scripts" / "github-forgejo-replica-sync.py"
if not SCRIPT.exists():
    SCRIPT = Path(__file__).with_name("github-forgejo-replica-sync.py")
spec = importlib.util.spec_from_file_location("replica", SCRIPT)
replica = importlib.util.module_from_spec(spec)
spec.loader.exec_module(replica)


class ReplicaIntegration(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.env = dict(os.environ, GIT_AUTHOR_NAME="Fixture", GIT_AUTHOR_EMAIL="fixture@example.invalid",
                        GIT_COMMITTER_NAME="Fixture", GIT_COMMITTER_EMAIL="fixture@example.invalid",
                        GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1")
        self.work = self.root / "work"
        self.source = self.root / "source.git"
        self.dest = self.root / "dest.git"
        replica.git(["init", "-b", "main", str(self.work)], self.env)
        replica.git(["commit", "--allow-empty", "-m", "initial"], self.env, self.work)
        replica.git(["clone", "--bare", str(self.work), str(self.source)], self.env)
        replica.git(["clone", "--bare", str(self.work), str(self.dest)], self.env)
        self.repo = {"name": "example", "source": str(self.source), "destination": str(self.dest)}
        self.config = {"state_dir": str(self.root / "state"), "min_free_bytes": 0}

    def tearDown(self):
        self.tmp.cleanup()

    def sync(self, run="test"):
        return replica.sync_repo(self.repo, self.config, run, self.env)

    def source_advance(self):
        replica.git(["commit", "--allow-empty", "-m", "advance"], self.env, self.work)
        replica.git(["push", str(self.source), "main"], self.env, self.work)

    def test_noop_does_not_create_recovery_bundle(self):
        result = self.sync()
        self.assertTrue(result["success"])
        self.assertEqual(result["changed_refs"], [])
        self.assertNotIn("preservation", result)

    def test_fast_forward_preserves_and_restore_verifies_old_main(self):
        before = replica.remote_refs(str(self.dest), self.env)
        self.source_advance()
        result = self.sync()
        self.assertEqual(result["preservation"]["refs"], before)
        self.assertTrue(result["preservation"]["verified"])
        self.assertEqual(replica.remote_refs(str(self.dest), self.env), replica.remote_refs(str(self.source), self.env))

    def test_divergent_destination_is_preserved_before_replacement(self):
        other = self.root / "other"
        replica.git(["clone", str(self.dest), str(other)], self.env)
        replica.git(["commit", "--allow-empty", "-m", "Forgejo-only work"], self.env, other)
        replica.git(["push", "origin", "main"], self.env, other)
        before = replica.remote_refs(str(self.dest), self.env)
        self.source_advance()
        result = self.sync()
        self.assertEqual(result["preservation"]["refs"], before)
        self.assertEqual(replica.remote_refs(str(self.dest), self.env), replica.remote_refs(str(self.source), self.env))

    def test_deleted_branch_and_tag_remain_in_recovery(self):
        replica.git(["branch", "local-only"], self.env, self.dest)
        replica.git(["tag", "v1.0.0"], self.env, self.dest)
        result = self.sync()
        preserved = result["preservation"]["refs"]
        self.assertIn("refs/heads/local-only", preserved)
        self.assertIn("refs/tags/v1.0.0", preserved)
        self.assertNotIn("refs/heads/local-only", replica.remote_refs(str(self.dest), self.env))
        self.assertNotIn("refs/tags/v1.0.0", replica.remote_refs(str(self.dest), self.env))

    def test_lease_race_rejects_entire_atomic_push(self):
        replica.git(["branch", "local-only"], self.env, self.dest)
        self.source_advance()
        original = replica.git
        # Create a distinct destination commit with a real object, then race to it.
        other = self.root / "other"
        original(["clone", str(self.dest), str(other)], self.env)
        original(["commit", "--allow-empty", "-m", "concurrent writer"], self.env, other)
        race_sha = original(["rev-parse", "HEAD"], self.env, other).strip()
        original(["push", "origin", "HEAD:refs/heads/race-object"], self.env, other)

        def actual_race(args, env, cwd=None):
            if args[0] == "push" and "--atomic" in args:
                original(["update-ref", "refs/heads/main", race_sha], self.env, self.dest)
            return original(args, env, cwd)

        with patch.object(replica, "git", side_effect=actual_race):
            with self.assertRaises(replica.SyncError):
                self.sync()
        after = replica.remote_refs(str(self.dest), self.env)
        self.assertEqual(after["refs/heads/main"], race_sha)
        self.assertIn("refs/heads/local-only", after)

    def test_failed_preservation_does_not_push(self):
        before = replica.remote_refs(str(self.dest), self.env)
        self.source_advance()
        with patch.object(replica, "preserve", side_effect=replica.SyncError("corrupt bundle")):
            with self.assertRaises(replica.SyncError):
                self.sync()
        self.assertEqual(replica.remote_refs(str(self.dest), self.env), before)

    def test_missing_source_main_does_not_delete_destination(self):
        before = replica.remote_refs(str(self.dest), self.env)
        replica.git(["update-ref", "-d", "refs/heads/main"], self.env, self.source)
        with self.assertRaises(replica.SyncError):
            self.sync()
        self.assertEqual(replica.remote_refs(str(self.dest), self.env), before)

    def test_insufficient_space_refuses_changes(self):
        self.source_advance()
        self.config["min_free_bytes"] = 2 ** 70
        before = replica.remote_refs(str(self.dest), self.env)
        with self.assertRaises(replica.SyncError):
            self.sync()
        self.assertEqual(replica.remote_refs(str(self.dest), self.env), before)

    def test_interrupted_push_is_reconciled_without_retry(self):
        self.source_advance()
        original = replica.git
        pushes = []

        def interrupted(args, env, cwd=None):
            output = original(args, env, cwd)
            if args[0] == "push":
                pushes.append(args)
                raise subprocess.TimeoutExpired("git push", 90)
            return output

        with patch.object(replica, "git", side_effect=interrupted):
            result = self.sync()
        self.assertTrue(result["success"])
        self.assertTrue(result["reconciled_push_error"])
        self.assertEqual(len(pushes), 1)

    def test_empty_destination_can_be_initialized(self):
        empty = self.root / "empty.git"
        replica.git(["init", "--bare", str(empty)], self.env)
        self.repo["destination"] = str(empty)
        result = self.sync()
        self.assertTrue(result["preservation"]["empty_destination"])
        self.assertEqual(replica.remote_refs(str(empty), self.env), replica.remote_refs(str(self.source), self.env))


class ConfigurationBoundary(unittest.TestCase):
    def config(self):
        return {"schema_version": 1, "authoritative": True, "state_dir": "/var/lib/replica",
                "known_hosts": "/etc/replica/known_hosts", "metrics_file": "/var/lib/metrics/replica.prom",
                "repositories": [{"name": "example", "source": "https://github.com/example/example.git",
                                  "destination": "git@forgejo:lab/example.git", "ssh_key": "/etc/replica/example"}]}

    def test_valid_explicit_scope(self):
        replica.validate_config(self.config())

    def test_rejects_implicit_authority_credentials_and_path_escape(self):
        for update in [{"name": "../example"}, {"source": "https://secret@github.com/example/example.git"}]:
            config = self.config()
            config["repositories"][0].update(update)
            with self.assertRaises(replica.SyncError):
                replica.validate_config(config)
        config = self.config()
        config["authoritative"] = False
        with self.assertRaises(replica.SyncError):
            replica.validate_config(config)

    def test_ssh_has_no_inherited_admin_identity_or_agent(self):
        config = self.config()
        command = replica.ssh_environment(config["repositories"][0], config)["GIT_SSH_COMMAND"]
        self.assertIn("-F /dev/null", command)
        self.assertIn("IdentityAgent=none", command)
        self.assertIn("StrictHostKeyChecking=yes", command)

    def test_rejects_shared_key_between_repositories(self):
        config = self.config()
        config["repositories"].append({"name": "second", "source": "https://github.com/example/second.git",
                                        "destination": "git@forgejo:lab/second.git", "ssh_key": "/etc/replica/example"})
        with self.assertRaises(replica.SyncError):
            replica.validate_config(config)

    def test_metrics_rejects_unknown_repositories_and_string_timestamps(self):
        config = self.config()
        status = {"success": True, "attempt_timestamp": 1, "last_success_timestamp": 1,
                  "repositories": {"unknown": {"success": True}}}
        with self.assertRaises(replica.SyncError):
            replica.write_metrics(config, status)
        status["repositories"] = {"example": {"success": True}}
        status["attempt_timestamp"] = "1\\ninjected_metric 1"
        with self.assertRaises(replica.SyncError):
            replica.write_metrics(config, status)


if __name__ == "__main__":
    unittest.main()
