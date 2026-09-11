#!/usr/bin/env python3
"""Validate repository-level GitHub controls against fleet/repositories.json.

The checker is deliberately read-only and stdlib-only. It validates hard invariants
(server-side branch protection, PR enforcement, no bypass actors, force-push/deletion
protection, and at least one required status check) and reports aggregate-gate drift
as an advisory until each repository is migrated explicitly in the manifest.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

API = "https://api.github.com"


def load_json(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        return json.load(handle)


def api_get(path: str, token: str | None) -> Any:
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "rmednitzer-infra-fleet-contract",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    request = urllib.request.Request(f"{API}{path}", headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"GET {path} -> HTTP {exc.code}: {body[:300]}") from exc
    except urllib.error.URLError as exc:
        raise RuntimeError(f"GET {path} failed: {exc.reason}") from exc


def rule_by_type(rules: list[dict[str, Any]], rule_type: str) -> dict[str, Any] | None:
    return next((rule for rule in rules if rule.get("type") == rule_type), None)


def required_contexts(rules: list[dict[str, Any]]) -> list[str]:
    rule = rule_by_type(rules, "required_status_checks")
    if not rule:
        return []
    checks = rule.get("parameters", {}).get("required_status_checks", [])
    return [str(check.get("context")) for check in checks if check.get("context")]


def validate_manifest_only(manifest: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if manifest.get("schema_version") != 1:
        errors.append("unsupported schema_version")
    owner = manifest.get("owner")
    if not isinstance(owner, str) or not owner:
        errors.append("owner must be a non-empty string")
    repos = manifest.get("repositories")
    if not isinstance(repos, list) or not repos:
        errors.append("repositories must be a non-empty list")
        return errors
    names: set[str] = set()
    for index, repo in enumerate(repos):
        if not isinstance(repo, dict):
            errors.append(f"repositories[{index}] must be an object")
            continue
        name = repo.get("name")
        if not isinstance(name, str) or not name:
            errors.append(f"repositories[{index}].name must be a non-empty string")
            continue
        if name in names:
            errors.append(f"duplicate repository: {name}")
        names.add(name)
        if not isinstance(repo.get("ruleset"), str) or not repo["ruleset"]:
            errors.append(f"{name}: ruleset must be a non-empty string")
        state = repo.get("aggregate_gate_state")
        if state not in {"enforced", "migration-pending", "planned"}:
            errors.append(f"{name}: invalid aggregate_gate_state {state!r}")
    return errors


def validate_repo(
    owner: str,
    repo_cfg: dict[str, Any],
    defaults: dict[str, Any],
    token: str | None,
) -> tuple[list[str], list[str]]:
    name = repo_cfg["name"]
    hard: list[str] = []
    advisory: list[str] = []

    metadata = api_get(f"/repos/{owner}/{name}", token)
    expected_branch = defaults.get("default_branch", "main")
    if metadata.get("default_branch") != expected_branch:
        hard.append(f"default branch is {metadata.get('default_branch')!r}, expected {expected_branch!r}")
    expected_visibility = defaults.get("visibility")
    if expected_visibility and metadata.get("visibility") != expected_visibility:
        hard.append(f"visibility is {metadata.get('visibility')!r}, expected {expected_visibility!r}")

    rulesets = api_get(f"/repos/{owner}/{name}/rulesets", token)
    wanted = repo_cfg["ruleset"]
    candidates = [item for item in rulesets if item.get("name") == wanted]
    if not candidates:
        hard.append(f"ruleset {wanted!r} not found")
        return hard, advisory

    ruleset_id = candidates[0].get("id")
    ruleset = api_get(f"/repos/{owner}/{name}/rulesets/{ruleset_id}", token)
    rules = ruleset.get("rules", [])

    if defaults.get("require_active_ruleset", True) and ruleset.get("enforcement") != "active":
        hard.append(f"ruleset enforcement is {ruleset.get('enforcement')!r}, expected 'active'")
    if defaults.get("require_no_bypass", True) and ruleset.get("bypass_actors"):
        hard.append(f"ruleset has bypass actors: {ruleset.get('bypass_actors')!r}")
    if defaults.get("require_pull_request", True) and not rule_by_type(rules, "pull_request"):
        hard.append("missing pull_request rule")
    if defaults.get("require_non_fast_forward", True) and not rule_by_type(rules, "non_fast_forward"):
        hard.append("missing non_fast_forward rule")
    if defaults.get("require_deletion_protection", True) and not rule_by_type(rules, "deletion"):
        hard.append("missing deletion protection rule")

    contexts = required_contexts(rules)
    if defaults.get("require_status_checks", True) and not contexts:
        hard.append("required_status_checks is absent or empty")

    preferred = repo_cfg.get("preferred_aggregate_context")
    gate_state = repo_cfg.get("aggregate_gate_state")
    if preferred and gate_state == "enforced" and contexts != [preferred]:
        hard.append(f"required contexts are {contexts!r}; enforced aggregate contract requires [{preferred!r}]")
    elif preferred and gate_state in {"planned", "migration-pending"} and contexts != [preferred]:
        advisory.append(f"aggregate migration pending: current={contexts!r}, target=[{preferred!r}]")

    if rule_by_type(rules, "required_linear_history") and metadata.get("allow_merge_commit"):
        advisory.append("merge commits are enabled although required_linear_history is enforced")

    if repo_cfg.get("lifecycle") == "archive-candidate" and not metadata.get("archived"):
        advisory.append(f"lifecycle={repo_cfg['lifecycle']}; superseded by {repo_cfg.get('superseded_by', 'unspecified')}")

    return hard, advisory


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", default="fleet/repositories.json")
    parser.add_argument("--manifest-only", action="store_true")
    parser.add_argument("--strict-advisories", action="store_true")
    args = parser.parse_args()

    manifest = load_json(Path(args.manifest))
    manifest_errors = validate_manifest_only(manifest)
    if manifest_errors:
        for error in manifest_errors:
            print(f"ERROR manifest: {error}")
        return 2
    if args.manifest_only:
        print(f"OK manifest: {len(manifest['repositories'])} repositories")
        return 0

    owner = manifest["owner"]
    defaults = manifest.get("defaults", {})
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    hard_count = 0
    advisory_count = 0

    for repo_cfg in manifest["repositories"]:
        name = repo_cfg["name"]
        try:
            hard, advisory = validate_repo(owner, repo_cfg, defaults, token)
        except RuntimeError as exc:
            hard = [str(exc)]
            advisory = []
        if not hard and not advisory:
            print(f"OK {owner}/{name}")
        else:
            for message in hard:
                hard_count += 1
                print(f"ERROR {owner}/{name}: {message}")
            for message in advisory:
                advisory_count += 1
                print(f"WARN {owner}/{name}: {message}")

    print(f"SUMMARY repositories={len(manifest['repositories'])} errors={hard_count} advisories={advisory_count}")
    if hard_count:
        return 1
    if args.strict_advisories and advisory_count:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
