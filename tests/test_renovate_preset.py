"""Keep custom CI-pin discovery narrow and independently regression tested."""
import json
from pathlib import Path
import re
import unittest

PRESET = json.loads((Path(__file__).parents[1] / "renovate-preset.json").read_text())


class WorkflowPinDiscovery(unittest.TestCase):
    def manager(self, datasource):
        return next(item for item in PRESET["customManagers"]
                    if item["datasourceTemplate"] == datasource)

    def matches(self, datasource, text):
        pattern = self.manager(datasource)["matchStrings"][0]
        # Python and RE2 use different spellings for named capture groups.
        pattern = re.sub(r"\(\?<([A-Za-z]+)>", r"(?P<\1>", pattern)
        return [match.groupdict() for match in re.finditer(pattern, text)]

    def test_python_pins_and_extras(self):
        self.assertEqual(self.matches("pypi", 'pip install "ruff==0.16.9" "coverage[toml]==7.6.0"'), [
            {"depName": "ruff", "currentValue": "0.16.9"},
            {"depName": "coverage", "currentValue": "7.6.0"},
        ])

    def test_npm_pin(self):
        self.assertEqual(self.matches("npm", "npx -y html-validate@11.16.1 index.html"), [
            {"depName": "html-validate", "currentValue": "11.16.1"},
        ])

    def test_does_not_update_binary_tags_or_digests(self):
        text = "bats_version=v1.13.0\nghcr.io/gitleaks/gitleaks@sha256:abc\ntflint_version: v0.64.0"
        self.assertEqual(self.matches("pypi", text), [])
        self.assertEqual(self.matches("npm", text), [])

    def test_workflow_files_only(self):
        for item in PRESET["customManagers"]:
            pattern = item["managerFilePatterns"][0][1:-1]
            self.assertRegex(".github/workflows/ci.yml", pattern)
            self.assertRegex(".github/workflows/ci.yaml", pattern)
            self.assertIsNone(re.search(pattern, "docs/example.yml"))
            self.assertIsNone(re.search(pattern, ".github/workflows/nested/ci.yml"))

    def test_age_and_major_review_policy_is_preserved(self):
        rules = PRESET["packageRules"]
        self.assertTrue(any(rule.get("minimumReleaseAge") == "3 days" for rule in rules))
        self.assertTrue(any(rule.get("matchUpdateTypes") == ["major"]
                            and rule.get("automerge") is False for rule in rules))
        self.assertFalse(PRESET["lockFileMaintenance"]["automerge"])


if __name__ == "__main__":
    unittest.main()
