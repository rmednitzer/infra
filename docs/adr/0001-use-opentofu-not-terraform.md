# ADR-0001: Use OpenTofu, not Terraform

- **Status**: Accepted
- **Date**: 2026-05-24

## Context

HashiCorp re-licensed Terraform from the Mozilla Public License (MPL
2.0) to the Business Source License (BSL) in August 2023. The BSL
restricts production use in software that competes with HashiCorp's
commercial offerings and is not OSI-approved. The Linux Foundation
forked the last MPL-licensed Terraform release into
[OpenTofu](https://opentofu.org/), which continues under MPL 2.0.

For `infra` we need a permissively-licensed infrastructure tool that:

- Supports HCL and the existing provider ecosystem we depend on (notably
  `dmacvicar/libvirt`).
- Has a stable release cadence and a credible long-term governance model.
- Carries no future license risk for commercial or internal-platform
  use.

OpenTofu satisfies all three: HCL-compatible, MPL-licensed, governed
under the Linux Foundation, shipping regular releases (1.12.0 at the
time of this ADR).

## Decision

Use **OpenTofu exclusively**. Every command in documentation, scripts,
CI, and day-to-day operations is `tofu …`. The Terraform CLI is not a
supported entry point.

Shared ecosystem conventions — HCL, the `.tf` extension, the
`terraform { }` block, `terraform.tfvars`, `.terraform/`,
`.terraform.lock.hcl` — are language artifacts, not Terraform endorsements.
OpenTofu reads and writes them natively.

## Consequences

**Positive**

- No license risk from HashiCorp's BSL.
- OpenTofu-specific features become available as we bump the version
  pin: state encryption (1.7), native S3 locking (1.10), ephemeral
  resources (1.11).
- Single, unambiguous command surface (`tofu`) in scripts and runbooks.

**Negative**

- Contributors arriving from Terraform-only backgrounds install the
  `tofu` binary and adjust muscle memory.
- Some providers publish only to the HashiCorp registry; OpenTofu's
  default registry mirrors most of them but we may need registry
  overrides for niche providers.

**Pinning**

- `required_version = ">= 1.6"` in every `versions.tf`. 1.6 is the first
  GA OpenTofu release. ADR-0003 may push this to `>= 1.10` once
  production adopts native S3 locking.

## References

- [OpenTofu announcement and license rationale](https://opentofu.org/blog/the-future-of-terraform-must-be-open/)
- [OpenTofu 1.6 GA release notes](https://opentofu.org/docs/intro/whats-new/)
- [HashiCorp BSL announcement](https://www.hashicorp.com/blog/hashicorp-adopts-business-source-license)
