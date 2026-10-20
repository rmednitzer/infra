# Contributing to `infra`

OpenTofu infrastructure layer — what gets created and destroyed. HCL
style and OpenTofu policy live in [`CLAUDE.md`](./CLAUDE.md); standing
decisions in [`docs/adr/`](./docs/adr/). This file is workflow only.

## Branch naming

| Prefix | Use |
|--------|-----|
| `feature/` | New modules, environments, providers |
| `fix/` | Bug fixes |
| `chore/` | CI / tooling / lint updates |
| `adr/` | ADR-only changes |

## Local loop

```bash
pip install -r requirements-dev.txt && pre-commit install
export PCT_TFPATH=tofu     # point pre-commit-terraform at OpenTofu
pre-commit run --all-files
```

CI mirrors the hook set — `tofu fmt`, `tofu validate`, `tflint`, Trivy
IaC, hygiene — plus `tofu test` for each module (`libvirt-vm`,
`talos-cluster`). PRs cannot merge with failing CI.

## Provider bumps

Lock files (`.terraform.lock.hcl`) must record `h1` hashes for every
platform a contributor or CI runner might use, not just the one that
last ran `tofu init`. **On every provider version change**, re-record
all common platforms in each root and commit the result:

```bash
for d in modules/libvirt-vm modules/talos-cluster environments/lab environments/production environments/talos-lab; do
  ( cd "$d" && tofu providers lock \
      -platform=linux_amd64 \
      -platform=darwin_amd64 \
      -platform=darwin_arm64 \
      -platform=linux_arm64 )
done
```

The libvirt-provider migration steps in
[ADR-0009](./docs/adr/0009-begin-libvirt-0.9-migration-evaluation.md)
call this out explicitly.

## Pull request expectations

1. `[Unreleased]` entry in [`CHANGELOG.md`](./CHANGELOG.md).
2. `pre-commit run --all-files` passes locally.
3. For architecturally significant changes (provider pin, backend
   strategy, module layout, cloud-init defaults), add an ADR using the
   Michael Nygard template and link it from the README ADR table.

PR template:
[`.github/PULL_REQUEST_TEMPLATE.md`](./.github/PULL_REQUEST_TEMPLATE.md).
Suspected vulnerabilities — see
[`.github/SECURITY.md`](./.github/SECURITY.md); never open a public
issue.

By contributing, you agree your contribution is licensed under
[Apache License 2.0](./LICENSE).


## Dependency automation

Renovate policy is owned by this repository in `renovate.json5`. It does not
inherit another project’s policy. Keep update grouping, release-age delays,
major-version review and lock-maintenance behavior explicit here. Built-in
Renovate presets supply standard defaults; repository-specific decisions remain
local. Review policy changes and actual dependency extraction before merging.


## CI run ownership

The PR-validation workflows updated here cancel superseded runs only for the
same pull request. Their push, scheduled and manual invocations use their own run
IDs so a newer revision cannot cancel verification or replace pending evidence.
Explicit diagnostic/publication serialization in other workflows remains separate. Reusable
workflows have distinct file prefixes to avoid cancelling a caller or sibling.
Cancelling an obsolete PR run is not a successful check; the current head still
needs all required results. Revision identity and signing gates remain separate.
Publication workflows retain their existing serialization and cache isolation.
Revert this repository's workflow change to restore the earlier scheduling;
no service deployment or application-data migration is involved.

The aggregate polls one paginated check snapshot per iteration. Its repository-owned
Python standard-library helper accepts only the requested revision and GitHub Actions
app, selects the newest check attempt, and refuses failures, malformed data and
unapproved skips. Missing or queued checks remain pending. API failures fail the gate.
Run its synthetic regressions with
`python3 -m unittest discover -s tests -p test_ci_checks.py`.

The fleet settings ledger records relay-shell's explicit direct required-check
set alongside its aggregate. The validator rejects missing, extra or duplicate
contexts and retains producer/freshness checks. Its optional admin inspection
requires Dependabot update PRs to remain disabled under Renovate ownership;
secret scanning and push protection remain required. This changes expected update
PR ownership, not vulnerability-alert availability. Public CI still reports the
limits of its read-only credential instead of claiming admin-setting verification.
