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
IaC, hygiene — plus `tofu test` for the `libvirt-vm` module. PRs cannot
merge with failing CI.

## Provider bumps

Lock files (`.terraform.lock.hcl`) must record `h1` hashes for every
platform a contributor or CI runner might use, not just the one that
last ran `tofu init`. **On every provider version change**, re-record
all common platforms in each root and commit the result:

```bash
for d in modules/libvirt-vm environments/lab environments/production; do
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
