## Description

<!-- What does this PR change, and why? -->

## Type of change

- [ ] New module
- [ ] Module improvement or refactor
- [ ] Bug fix
- [ ] Environment configuration change
- [ ] Documentation update
- [ ] CI / tooling change

## Checklist

- [ ] Follows the [HCL conventions](/rmednitzer/infra/blob/main/CLAUDE.md)
- [ ] Read the relevant [ADR(s)](/rmednitzer/infra/tree/main/docs/adr) if
      this PR changes a standing convention (provider pin, backend
      strategy, module layout, cloud-init defaults); either follows the
      existing ADR or proposes a new ADR that supersedes it
- [ ] `tofu fmt -recursive` is clean
- [ ] `tofu validate` passes for every touched module and environment
- [ ] `tofu plan` reviewed for any environment change
- [ ] All variables have `description` and `type`
- [ ] All outputs have `description`
- [ ] Sensitive values marked `sensitive = true` and not hardcoded
- [ ] No state files included in this PR
- [ ] `[Unreleased]` entry added to [`CHANGELOG.md`](/rmednitzer/infra/blob/main/CHANGELOG.md)
- [ ] Relevant documentation updated (module READMEs, ADRs, etc.)

## Plan output

<!-- Paste relevant `tofu plan` output or summary -->

## Additional notes

<!-- Anything else worth knowing -->
