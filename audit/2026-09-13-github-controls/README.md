# GitHub configuration audit — 2026-09-13

## Scope and result

Live authenticated inventory: eight owned public repositories. All eight have
active default-branch rulesets, PR enforcement, no bypass actors, linear history,
required status checks, and force-push/deletion protection. Workflow tokens default
to read-only and cannot approve PRs. Secret scanning, push protection and
Dependabot security updates are enabled. No open Dependabot or secret-scanning
alerts were returned. No repository self-hosted runners or webhooks were returned.

All eight repositories use the shared infra:renovate-preset. All workflow and
composite-action references inspected are SHA-pinned. Actionlint passed for all
eight repositories; shellcheck and pyflakes integrations were disabled.

## Applied repository settings

For each of the eight repositories, read-back verified:

- sha_pinning_required: false → true.
- allow_merge_commit: true → false, matching enforced linear history.
- allow_update_branch: false → true.

Previous values are in settings-before/. These contain configuration only,
without credentials. Existing squash and rebase merge options remain enabled.

## Prepared fixes

- Remove workflow-level path filters from Fleet Contract: the aggregate gate
  requires its checks, so it must run for every main-targeted PR.
- Verify that the selected ruleset targets branches and includes the default
  branch without excluding it. Five regression tests cover wrong targets,
  exclusions, explicit refs and the default/all selectors.
- Repair automation PR #76 by replacing API polling with a native needs gate
  inside CI. Its previous 25-minute polling deadline expired before the successful
  Molecule common job finished. The new gate also covers compliance, vault and SBOM
  jobs and rejects failed, cancelled or skipped dependencies.

## Outstanding evidence and blockers

The unchanged fleet manifest contains 11 repositories. ai-stack, aiops-mcp
and renovate-config return HTTP 404 using the existing Vertex credential and do
not appear in the connected inventory. A 404 does not establish deletion versus
restricted visibility or migration. Their intended disposition needs confirmation;
the checker continues to fail rather than silently removing these requirements.

Automation's ruleset still requires its existing individual checks. Migrate it
to ci-success only after the repaired PR passes and lands. Do not weaken existing
checks to merge either change.

Core-graph CodeQL alert 1 remains open (high, clear-text logging). The inspected
secret-scanner path passes a constant detection label and relative filename,
not matched contents, to its logger. Inferred: that reported path is a false
positive. The alert was not dismissed. The separate YAML exception diagnostic
can include source excerpts; assess that before treating all validator diagnostics
as safe for secret-bearing input.

Account-level 2FA status was absent from the authenticated API response, so it
was not verified. This review does not certify account sessions, PAT inventory,
billing, or backup/restore completeness. Repository environments were counted,
but deployment secrets were not read or modified.

## Rollback

Run python3 rollback-settings.py --apply from this directory with an
appropriately authenticated gh. Without --apply, the script prints the
planned settings only. It restores only the three settings changed by this audit.
Revert the corresponding PR commits to roll back code changes.

## References

- [GitHub Actions secure use](https://docs.github.com/en/actions/reference/security/secure-use)
- [Repository Actions policies](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)
- [Protected branches and linear history](https://docs.github.com/repositories/configuring-branches-and-merges-in-your-repository/defining-the-mergeability-of-pull-requests/about-protected-branches)
- [Automation PR 76](https://github.com/rmednitzer/automation/pull/76)
- [Core-graph alert 1](https://github.com/rmednitzer/core-graph/security/code-scanning/1)
