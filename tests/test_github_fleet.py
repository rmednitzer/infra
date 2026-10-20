"""Regression tests for default-branch ruleset coverage."""
import copy
import json
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
            "rules": [{"type": t} for t in ("pull_request", "non_fast_forward", "deletion", "required_linear_history")]
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

    def test_missing_linear_history_is_rejected(self):
        self.ruleset["rules"] = [
            rule for rule in self.ruleset["rules"]
            if rule["type"] != "required_linear_history"
        ]
        self.assertIn("missing required_linear_history rule", self.errors())

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


class ReleaseTagPolicy(unittest.TestCase):
    def test_active_protection_and_negative_cases(self):
        branch = {
            "target": "branch", "enforcement": "active", "bypass_actors": [],
            "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
            "rules": [{"type": name} for name in
                      ("pull_request", "non_fast_forward", "deletion", "required_linear_history")]
            + [{"type": "required_status_checks", "parameters": {
                "required_status_checks": [{"context": "ci-success"}]}}],
        }
        tag = {
            "target": "tag", "enforcement": "active", "bypass_actors": [],
            "conditions": {"ref_name": {"include": ["refs/tags/v*"], "exclude": []}},
            "rules": [{"type": "update"}, {"type": "deletion"}],
        }
        summary = [
            {"id": 1, "name": "main-protection"},
            {"id": 2, "name": "release-tag-integrity"},
        ]
        repo = {"name": "repo", "ruleset": "main-protection",
                "release_tag_ruleset": "release-tag-integrity",
                "preferred_aggregate_context": "ci-success",
                "aggregate_gate_state": "enforced"}
        def check():
            with patch.object(fleet, "api_get", side_effect=[
                {"default_branch": "main", "visibility": "public"},
                summary, copy.deepcopy(branch), copy.deepcopy(tag),
            ]):
                errors, _ = fleet.validate_repo("owner", repo, {}, None)
            return errors
        self.assertEqual(check(), [])
        for field, replacement in [
            ("enforcement", "disabled"), ("target", "branch"),
            ("bypass_actors", [{"actor_id": 1}]),
        ]:
            with self.subTest(field=field):
                original = tag[field]
                tag[field] = replacement
                self.assertTrue(check())
                tag[field] = original
        tag["rules"] = [{"type": "deletion"}]
        self.assertIn("release tag ruleset missing update protection", check())
        tag["rules"] = [{"type": "update"}]
        self.assertIn("release tag ruleset missing deletion protection", check())


class ImmutableOidcPolicy(unittest.TestCase):
    def test_immutable_oidc_expected_in_manifest(self):
        import json
        manifest = json.loads((pathlib.Path(__file__).parents[1] / "fleet/repositories.json").read_text())
        protected = {"automation", "infra", "runbooks", "6dof-ascent-sim", "rmednitzer.github.io"}
        for repo in manifest["repositories"]:
            if repo["name"] in protected:
                self.assertIs(repo.get("require_immutable_oidc_subject"), True)


class ReleaseCreators(unittest.TestCase):
    def test_creation_rule_and_scope(self):
        branch = {
            "target": "branch", "enforcement": "active", "bypass_actors": [],
            "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
            "rules": [{"type": t} for t in
                      ("pull_request", "non_fast_forward", "deletion", "required_linear_history")]
            + [{"type": "required_status_checks", "parameters": {
                "required_status_checks": [{"context": "ci-success"}]}}],
        }
        creator = {
            "target": "tag", "enforcement": "active",
            "conditions": {"ref_name": {"include": ["refs/tags/v*"], "exclude": []}},
            "rules": [{"type": "creation"}],
        }
        rulesets = [{"id": 1, "name": "main-protection"},
                    {"id": 2, "name": "release-tag-creators"}]
        cfg = {
            "name": "repo", "ruleset": "main-protection",
            "release_creator_ruleset": "release-tag-creators",
        }
        def check():
            with patch.object(fleet, "api_get", side_effect=[
                {"default_branch": "main", "visibility": "public"},
                rulesets, copy.deepcopy(branch), copy.deepcopy(creator),
            ]):
                return fleet.validate_repo("owner", cfg, {}, None)[0]
        self.assertEqual(check(), [])
        creator["rules"] = []
        self.assertIn("release creator ruleset does not restrict tag creation", check())
        creator["rules"] = [{"type": "creation"}]
        creator["conditions"]["ref_name"]["include"] = ["refs/tags/other*"]
        self.assertIn("release creator ruleset has incorrect tag scope", check())


class FleetStrictPolicy(unittest.TestCase):
    def test_all_repositories_require_up_to_date_checks(self):
        manifest = json.loads((pathlib.Path(__file__).parents[1] / "fleet/repositories.json").read_text())
        self.assertIs(manifest["defaults"]["require_up_to_date"], True)
        for repo in manifest["repositories"]:
            with self.subTest(repo=repo["name"]):
                self.assertIsNot(repo.get("require_up_to_date", True), False)


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

    def test_dependabot_pause_is_rejected(self):
        policy = {"dependabot_unpaused": True}
        metadata = {}
        cases = [
            ({"enabled": True, "paused": False}, []),
            ({"enabled": True, "paused": True}, ["Dependabot security updates disabled or paused"]),
        ]
        for state, expected in cases:
            with self.subTest(state=state):
                with patch.object(fleet, "api_get", side_effect=[{}, {}, state]):
                    self.assertEqual(
                        fleet.validate_admin_controls("o", "r", metadata, policy, None),
                        expected,
                    )

    def test_api_denial_does_not_pass(self):
        with patch.object(fleet, "api_get", side_effect=RuntimeError("HTTP 403")):
            with self.assertRaises(RuntimeError):
                fleet.validate_admin_controls("o", "r", {}, {}, None)


if __name__ == "__main__":
    unittest.main()


class ExplicitCheckContracts(unittest.TestCase):
    def test_exact_context_set_rejects_missing_extra_or_duplicate_checks(self):
        fixture = RulesetCoverage()
        fixture.setUp()
        cfg = {"name": "repo", "ruleset": "main-protection",
               "preferred_aggregate_context": "ci-success", "aggregate_gate_state": "enforced",
               "required_contexts": ["ci-success", "security"]}
        for contexts, accepted in [
            (["security", "ci-success"], True),
            (["ci-success"], False),
            (["ci-success", "security", "extra"], False),
            (["ci-success", "security", "security"], False),
        ]:
            with self.subTest(contexts=contexts):
                rules = copy.deepcopy(fixture.ruleset)
                rules["rules"][-1]["parameters"]["required_status_checks"] = [
                    {"context": name} for name in contexts]
                with patch.object(fleet, "api_get", side_effect=[
                    {"default_branch": "main", "visibility": "public"},
                    [{"id": 1, "name": "main-protection"}], rules,
                ]):
                    errors, _ = fleet.validate_repo("owner", cfg, {}, None)
                self.assertEqual(not errors, accepted)

    def test_manifest_refuses_empty_duplicate_or_aggregate_omitting_contract(self):
        for checks in [[], ["ci-success", "ci-success"], ["security"], "ci-success"]:
            with self.subTest(checks=checks):
                manifest = {"schema_version": 1, "owner": "owner", "repositories": [{
                    "name": "repo", "ruleset": "main-protection", "aggregate_gate_state": "enforced",
                    "preferred_aggregate_context": "ci-success", "required_contexts": checks}]}
                self.assertTrue(fleet.validate_manifest_only(manifest))

    def test_disabled_dependabot_pr_policy_is_enforced_not_ignored(self):
        policy = {"dependabot_enabled": False}
        for enabled, accepted in [(False, True), (True, False), (None, False)]:
            with self.subTest(enabled=enabled):
                with patch.object(fleet, "api_get", side_effect=[{}, {}, {"enabled": enabled}]):
                    errors = fleet.validate_admin_controls("owner", "repo", {}, policy, None)
                self.assertEqual(not errors, accepted)
