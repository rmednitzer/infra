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

    def errors(self):
        replies = [
            {"default_branch": "main", "visibility": "public"},
            [{"id": 1, "name": "main-protection"}], copy.deepcopy(self.ruleset),
        ]
        with patch.object(fleet, "api_get", side_effect=replies):
            errors, _ = fleet.validate_repo(
                "owner", {"name": "repo", "ruleset": "main-protection",
                          "preferred_aggregate_context": "ci-success",
                          "aggregate_gate_state": "enforced"}, {}, None
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


if __name__ == "__main__":
    unittest.main()
