"""Regression tests for default-branch ruleset coverage."""
import copy
import importlib.util
import pathlib
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "fleet", pathlib.Path(__file__).parents[1] / "scripts/check-github-fleet.py"
)
fleet = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(fleet)


class RulesetCoverage(unittest.TestCase):
    def setUp(self):
        self.ruleset = {
            "target": "branch", "enforcement": "active", "bypass_actors": [],
            "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
            "rules": [{"type": t} for t in ("pull_request", "non_fast_forward", "deletion")]
            + [{"type": "required_status_checks", "parameters": {
                "required_status_checks": [{"context": "ci-success"}]}}],
        }

    def errors(self, defaults=None):
        replies = [
            {"default_branch": "main", "visibility": "public"},
            [{"id": 1, "name": "main-protection"}], copy.deepcopy(self.ruleset),
        ]
        with patch.object(fleet, "api_get", side_effect=replies):
            errors, _ = fleet.validate_repo(
                "owner", {"name": "repo", "ruleset": "main-protection",
                          "preferred_aggregate_context": "ci-success",
                          "aggregate_gate_state": "enforced"}, defaults or {}, None
            )
        return errors

    def test_default_branch_is_protected(self):
        self.assertEqual(self.errors(), [])

    def test_wrong_ref_is_rejected(self):
        self.ruleset["conditions"]["ref_name"]["include"] = ["refs/heads/develop"]
        self.assertTrue(self.errors())

    def test_default_branch_exclusion_is_rejected(self):
        for excluded in ["~DEFAULT_BRANCH", "~ALL", "refs/heads/main", "refs/heads/*"]:
            with self.subTest(excluded=excluded):
                self.ruleset["conditions"]["ref_name"]["exclude"] = [excluded]
                self.assertTrue(self.errors())

    def test_tag_ruleset_is_rejected(self):
        self.ruleset["target"] = "tag"
        self.assertTrue(self.errors())

    def test_explicit_ref_and_all_are_accepted(self):
        for included in ["refs/heads/main", "~ALL"]:
            with self.subTest(included=included):
                self.ruleset["conditions"]["ref_name"]["include"] = [included]
                self.assertEqual(self.errors(), [])

    def test_check_source_binding(self):
        defaults = {"required_check_integration_id": 15368}
        self.assertTrue(self.errors(defaults))
        check = self.ruleset["rules"][-1]["parameters"]["required_status_checks"][0]
        check["integration_id"] = 15368
        self.assertEqual(self.errors(defaults), [])
        check["integration_id"] = 1
        self.assertTrue(self.errors(defaults))

    def test_strict_policy(self):
        defaults = {"require_up_to_date": True}
        self.assertTrue(self.errors(defaults))
        self.ruleset["rules"][-1]["parameters"]["strict_required_status_checks_policy"] = True
        self.assertEqual(self.errors(defaults), [])


class AdminControls(unittest.TestCase):
    def test_matches_and_missing_values(self):
        policy = {
            "repository": {"allow_merge_commit": False},
            "actions": {"sha_pinning_required": True},
            "workflow": {"default_workflow_permissions": "read"},
            "security": ["secret_scanning"],
        }
        metadata = {"allow_merge_commit": False,
                    "security_and_analysis": {"secret_scanning": {"status": "enabled"}}}
        with patch.object(fleet, "api_get", side_effect=[
            {"sha_pinning_required": True}, {"default_workflow_permissions": "read"}
        ]):
            self.assertEqual(fleet.validate_admin_controls("o", "r", metadata, policy, None), [])
        with patch.object(fleet, "api_get", side_effect=[{}, {}]):
            errors = fleet.validate_admin_controls("o", "r", {}, policy, None)
        self.assertEqual(len(errors), 4)

    def test_api_denial_does_not_pass(self):
        with patch.object(fleet, "api_get", side_effect=RuntimeError("HTTP 403")):
            with self.assertRaises(RuntimeError):
                fleet.validate_admin_controls("o", "r", {}, {}, None)


if __name__ == "__main__":
    unittest.main()
