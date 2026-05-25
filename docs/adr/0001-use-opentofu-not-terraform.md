# ADR-0001: Use OpenTofu, not Terraform

- **Status**: Accepted
- **Date**: 2026-05-24

## Context

HashiCorp re-licensed Terraform from the Mozilla Public License (MPL 2.0) to the
Business Source License (BSL) in August 2023. The BSL restricts production use
in software that competes with HashiCorp's commercial offerings and is not an
OSI-approved open-source license. In response, the Linux Foundation forked the
last MPL-licensed Terraform release into [OpenTofu](https://opentofu.org/),
which has continued under the original MPL 2.0 license.

For `infra` we need a permissively-licensed infrastructure tool that:

- Supports the HashiCorp Configuration Language (HCL) and the existing provider
  ecosystem we depend on (notably `dmacvicar/libvirt`).
- Has a stable release cadence and a credible long-term governance model.
- Carries no future license risk for commercial or internal-platform use.

OpenTofu satisfies all three: HCL-compatible, MPL-licensed, governed under the
Linux Foundation, and shipping regular releases (1.12.0 was current at the time
of this ADR).

## Decision

Use **OpenTofu exclusively**. All commands in documentation, scripts, CI, and
day-to-day operations are `tofu …`. The Terraform CLI is not a supported entry
point for this repository.

We treat the shared ecosystem conventions — HCL, the `.tf` file extension, the
`terraform { }` block, the `terraform.tfvars` filename, the `.terraform/`
working directory, and the `.terraform.lock.hcl` lock file — as language
artifacts, not as endorsements of the Terraform CLI. These names are preserved
because OpenTofu reads and writes them natively.

## Consequences

**Positive**

- No license risk from HashiCorp's BSL.
- OpenTofu-specific features (state encryption from 1.7, native S3 locking from
  1.10, ephemeral resources from 1.11) become available as we bump the version
  pin.
- A single, unambiguous command surface (`tofu`) in scripts and runbooks.

**Negative**

- Contributors arriving from Terraform-only backgrounds must install the
  `tofu` binary and adjust muscle memory.
- Providers occasionally publish to the HashiCorp registry only; OpenTofu's
  default registry mirrors most of them but we may need to add registry
  overrides for niche providers.

**Pinning**

- `required_version = ">= 1.6"` in every `versions.tf`. 1.6 is the first
  GA OpenTofu release; we have no current need to require a newer minimum,
  but ADR-0003 may push this to `>= 1.10` once production adopts native S3
  locking.

## References

- [OpenTofu announcement and license rationale](https://opentofu.org/blog/the-future-of-terraform-must-be-open/)
- [OpenTofu 1.6 GA release notes](https://opentofu.org/docs/intro/whats-new/)
- [HashiCorp BSL announcement](https://www.hashicorp.com/blog/hashicorp-adopts-business-source-license)
