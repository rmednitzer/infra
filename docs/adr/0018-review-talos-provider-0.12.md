# ADR-0018: Review Talos provider 0.12 for the repository baseline

- **Status**: Accepted for repository configuration; live acceptance required before deployment
- **Date**: 2026-10-04
- **Supersedes**: The version pin in ADR-0014, not its live-acceptance requirement

## Context and options

The stable `siderolabs/talos` 0.12.0 release was published on 2026-09-21.
ADR-0014 requires an explicit review for a pre-1.0 minor upgrade. Keeping
0.11.x is the do-nothing option. Adopting the new combined `talos_machine`
or `talos_cluster` resources would require a separate state and resource-graph
migration; that option is not part of this maintenance change.

## Decision

Update the module and lab environment to `~> 0.12.0`, retaining patch-level
pinning. Refresh both provider locks for Linux and macOS on amd64 and arm64.
The libvirt provider selection and lock blocks remain unchanged. Talos and
Kubernetes versions, node images, topology, resource addresses, backend
configuration, hardening, and persisted output contracts are unchanged.

Retain ADR-0017's write-only arguments on configuration-apply and bootstrap.
The regular `talos_cluster_kubeconfig` resource still requires persisted
`client_configuration`; its 0.12.0 schema provides no write-only alternative.
Ephemeral client configuration, health, kubeconfig, machine configuration,
and machine secrets remain deferred: their adoption changes the persisted
output contract and operator workflow. ADR-0015's backend requirements remain
in force. No new combined resource is introduced.

## Evidence and boundary

Validation used the repository-pinned OpenTofu 1.12.1 in an isolated checkout,
with backend initialization disabled and without live cluster credentials.

- All six resource/data schemas used by the module are structurally unchanged
  between 0.11.0 and 0.12.0, including nested attributes. The comparison
  excludes documentation metadata only.
- Both configuration-apply arguments and the bootstrap argument retain their
  `write_only` flags.
- `tofu validate` passed for the module and lab environment.
- The real-schema, mock-provider Talos suite passed **46/46** tests, including
  the existing hardening and write-only argument assertions.
- Provider locks were refreshed for `linux_amd64`, `linux_arm64`,
  `darwin_amd64`, and `darwin_arm64`; the libvirt lock blocks are unchanged.

This proves configuration and schema compatibility, not live equivalence.
No live plan, apply, bootstrap, reset, or state migration was performed.
Review the first plan against real lab state and complete live acceptance
before deployment, as ADR-0014 requires. Identical schemas do not prove
identical generated configurations or behavior across provider SDK versions.

## Consequences, scope, and rollback

The two Talos roots can test the current stable provider without silently
widening their compatibility range. This changes future initialization and
planning, not the configuration of an existing host.

Rollback before deployment is a PR reverting the constraints and both lock
files together. No runtime rollback is needed for this repository-only
change. After a future apply, rollback requires a state-aware plan; a Git
revert alone is not a deployed-state rollback.

## References

- [ADR-0014](0014-pin-siderolabs-talos-provider.md)
- [ADR-0015](0015-talos-machineconfig-as-code-and-secrets.md)
- [ADR-0017](0017-adopt-talos-write-only-secret-arguments.md)
- [Provider 0.12.0 release](https://github.com/siderolabs/terraform-provider-talos/releases/tag/v0.12.0)
