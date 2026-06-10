# ADR-0014: Pin `siderolabs/talos` to `~> 0.11.0`

- **Status**: Accepted
- **Date**: 2026-05-30

> **Note (2026-06-09, BACKLOG BL-2 outcome):** the provider's write-only
> secret arguments (`client_configuration_wo`,
> `machine_configuration_input_wo`) were evaluated and **adopted** within the
> `~> 0.11.0` pin — see
> [ADR-0017](0017-adopt-talos-write-only-secret-arguments.md). The pin and
> the migration plan below are unchanged; when the 0.12.x bump is reviewed,
> also re-assess the items ADR-0017 defers (a `_wo` variant on
> `talos_cluster_kubeconfig`, and the ephemeral resource variants).

## Context

[ADR-0013](0013-adopt-talos-linux.md) adopts Talos Linux and introduces
the `modules/talos-cluster` module, which depends on the
partner-verified [`siderolabs/talos`](https://registry.terraform.io/providers/siderolabs/talos)
provider to generate machine secrets/config, apply config over the Talos
API, bootstrap etcd, and export the kubeconfig/talosconfig.

`siderolabs/talos` is **pre-1.0**. As with `dmacvicar/libvirt`
([ADR-0002](0002-pin-libvirt-provider-to-0.8.md)), semantic versioning
does not guarantee backward compatibility across minor versions for a
pre-1.0 provider; a minor bump is the author's signal that breaking
changes may have shipped. The provider has in fact moved interfaces
across minors — e.g. `talos_cluster_kubeconfig` migrated from a **data
source** to a **resource** (the data source is now deprecated and slated
for removal in a later minor), which the module had to account for.

Version state at the time of this ADR (Terraform registry, the
authoritative registry for this provider; cross-checked 2026-05-30):

| Channel | Version |
|---------|---------|
| Latest stable | **0.11.0** |
| Latest pre-release | 0.12.0-alpha.1 (2026-05-19) |

(The OpenTofu registry mirror lagged at 0.3.2 at the time of writing;
the provider resolves and installs fine from it, but the Terraform
registry is the source of truth for the current version.)

## Decision

Pin `siderolabs/talos` to **`~> 0.11.0`** (i.e. `>= 0.11.0, < 0.12.0`)
in `modules/talos-cluster/versions.tf` and in
`environments/talos-lab/versions.tf`:

```hcl
talos = {
  source  = "siderolabs/talos"
  version = "~> 0.11.0"
}
```

The constraint is at the **patch** level (`~> 0.11.0`, not `~> 0.11`),
**deliberately**, consistent with ADR-0002's pre-1.0 pin rule and
`CLAUDE.md`. Only 0.11.x patch releases (bug fixes) can land without an
explicit pin change; a 0.12.x bump is an opt-in decision.

The committed `.terraform.lock.hcl` in both roots records `0.11.0` with
`h1` hashes for `linux_amd64`, `darwin_amd64`, `darwin_arm64`, and
`linux_arm64` (via `tofu providers lock`), matching the multi-platform
lock convention already used for libvirt.

The resource schema was verified against the 0.11.0 provider
documentation before the module was written:
`talos_machine_secrets` (exports `machine_secrets`,
`client_configuration`), `data.talos_machine_configuration`
(`cluster_name`, `cluster_endpoint`, `machine_type`, `machine_secrets`,
`talos_version`, `kubernetes_version`, `config_patches` → exports
`machine_configuration`), `talos_machine_configuration_apply`
(`client_configuration`, `machine_configuration_input`, `node`,
`endpoint`, `config_patches`, `apply_mode`), `talos_machine_bootstrap`
(`node`, `endpoint`, `client_configuration`), `talos_cluster_kubeconfig`
(resource form; `node`, `endpoint`, `client_configuration` → exports
`kubeconfig_raw`), and `data.talos_client_configuration`
(`cluster_name`, `client_configuration`, `endpoints`, `nodes` → exports
`talos_config`). `tofu validate` against 0.11.0 is clean.

## Consequences

**Positive**

- Predictable upgrades: only 0.11.x patches land automatically;
  reproducible via the committed lock file.
- No exposure to a 0.12.x interface change (like the kubeconfig
  data-source→resource move) during routine `tofu init`.
- Consistent with the libvirt pin discipline, so the two pre-1.0
  providers are governed by the same rule.

**Negative**

- We do not get 0.12.x features/fixes until we explicitly bump.
- The provider's pre-1.0 churn means a bump may be needed relatively
  often; each is a reviewed pin change with a lock refresh.

## Migration plan (when we move to 0.12.x)

1. Confirm the 0.12.x changelog for breaking changes (the kubeconfig
   resource move is already absorbed; watch for further interface
   shifts).
2. Change `version = "~> 0.11.0"` to `~> 0.12.0` in both
   `talos-cluster` and `talos-lab`.
3. `tofu init -upgrade` to refresh `.terraform.lock.hcl`; commit the
   new hashes.
4. `tofu validate` + `tofu test` (mock-provider suite) must pass, then
   re-verify on a real cluster before any production bump.

## References

- [ADR-0002 — Pin `dmacvicar/libvirt` to `~> 0.8.0`](0002-pin-libvirt-provider-to-0.8.md)
- [ADR-0013 — Adopt Talos Linux](0013-adopt-talos-linux.md)
- [`siderolabs/talos` provider on the Terraform registry](https://registry.terraform.io/providers/siderolabs/talos)
- [OpenTofu version constraints](https://opentofu.org/docs/language/expressions/version-constraints/)
