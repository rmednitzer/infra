# ADR-0002: Pin `dmacvicar/libvirt` to `~> 0.8.0`

- **Status**: Accepted
- **Date**: 2026-05-24

## Context

The KVM/libvirt VM provisioning module depends on the community-maintained
[`dmacvicar/libvirt`](https://github.com/dmacvicar/terraform-provider-libvirt)
provider. The provider is pre-1.0, which means semantic versioning does not
guarantee backward compatibility across minor versions.

At the time of this ADR the provider has two active release branches:

| Branch | Latest | Notes |
|--------|--------|-------|
| 0.8.x | 0.8.3 (Mar 2026) | Original architecture, mature, widely deployed |
| 0.9.x | 0.9.7 (Mar 2026) | Major redesign on the new Terraform plugin framework; full libvirt API surface; **schema-breaking** |

Per the provider's release notes, 0.9.0 is "a breaking redesign with new
plugin framework" — state migration, attribute renames, and resource-shape
changes are involved. The 0.9.x series is still stabilising (seven point
releases in five months).

We do not currently need any 0.9.x-only capability (XML code generation,
graceful shutdown, configurable shutdown timeouts, pool lifecycle controls).
All of our resources — `libvirt_domain`, `libvirt_volume`,
`libvirt_cloudinit_disk` — are well-supported by 0.8.x.

## Decision

Pin the libvirt provider to `~> 0.8.0` (i.e. `>= 0.8.0, < 0.9.0`) in
`modules/libvirt-vm/versions.tf` and every environment root's `versions.tf`.

The pessimistic constraint at the **patch** level — `~> 0.8.0`, **not** `~> 0.8`
— is deliberate: for pre-1.0 providers, a minor-version bump is the
provider author's signal that breaking changes have shipped.

## Consequences

**Positive**

- Predictable upgrade path: only 0.8.x patch releases (bug fixes) can land
  without an explicit version pin change.
- The committed `.terraform.lock.hcl` files pin to exact hashes within the
  allowed range, so `tofu init` is reproducible across machines.
- No exposure to 0.9.x state-migration risk during routine `tofu init`.

**Negative**

- We do not benefit from 0.9.x improvements (XML overrides, graceful shutdown,
  better import semantics) until we explicitly migrate.
- 0.8.x will eventually go unmaintained. We need to plan the 0.9.x migration
  before that happens.

## Migration plan (when we move to 0.9.x)

1. Open a new ADR (`0007-…`) capturing the migration decision and superseding
   this one.
2. Run `tofu plan` against a 0.9.x build in the lab environment first.
   Expect schema diffs even with no functional change.
3. Use `tofu state mv` / `tofu state rm` + import where attribute renames
   require it; never hand-edit state.
4. Update both module and environment `versions.tf` files in the same change.
5. Refresh `.terraform.lock.hcl` in every environment (`tofu init -upgrade`)
   and commit the new hashes.

## References

- [terraform-provider-libvirt releases](https://github.com/dmacvicar/terraform-provider-libvirt/releases)
- [OpenTofu version constraints](https://opentofu.org/docs/language/expressions/version-constraints/)
- `.github/copilot-instructions.md` — pin convention for pre-1.0 providers
