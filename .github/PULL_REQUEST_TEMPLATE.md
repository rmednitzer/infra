## Description

<!-- Describe the changes in this PR -->

## Type of Change

- [ ] New module
- [ ] Module improvement or refactor
- [ ] Environment configuration change
- [ ] Documentation update
- [ ] CI / tooling change

## Checklist

- [ ] I have followed the [HCL conventions](../CLAUDE.md) for this project
- [ ] I have read the relevant [ADR(s)](../docs/adr/) if this PR changes
      a standing convention (provider pin, backend strategy, module
      layout, cloud-init defaults), and either follows the existing ADR
      or proposes a new ADR that supersedes it
- [ ] `tofu fmt -recursive` is clean
- [ ] `tofu validate` passes for every touched module and environment
- [ ] `tofu plan` was reviewed for any environment change
- [ ] All variables have `description` and `type` defined
- [ ] All outputs have `description` defined
- [ ] Sensitive values are marked `sensitive = true` and not hardcoded
- [ ] No state files are included in this PR
- [ ] `[Unreleased]` entry added to [`CHANGELOG.md`](../CHANGELOG.md)
- [ ] Relevant documentation updated (module READMEs, ADRs, etc.)

## Plan Output

<!-- Paste relevant `tofu plan` output or summary -->

## Additional Notes

<!-- Any other context about this PR -->
