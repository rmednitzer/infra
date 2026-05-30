# ADR-0013: Adopt Talos Linux for the Kubernetes layer (coexists with libvirt/Ubuntu)

- **Status**: Accepted
- **Date**: 2026-05-30

## Context

`infra` provisions KVM/libvirt VMs and is deliberately decoupled from
configuration management: `modules/libvirt-vm` delivers a reachable,
cloud-init-bootstrapped Ubuntu VM, and the `automation` (Ansible) repo
hardens and configures it ([ADR-0004](0004-cloud-init-bootstrap-conventions.md)).
That split is the right shape for general-purpose Linux hosts.

For the **Kubernetes layer** specifically, a different model is now on
the table: [Talos Linux](https://www.talos.dev/). Talos is a minimal,
immutable, API-managed OS purpose-built to run Kubernetes:

- **No SSH, no shell, no PAM, no package manager.** The entire
  general-purpose userspace — and the attack surface that comes with it —
  is gone.
- **Immutable, read-only rootfs.** The OS is not mutated in place;
  changes are declarative.
- **API-only configuration.** A node is configured by a single
  declarative *machine configuration* applied over the Talos API
  (`talosctl` or the `siderolabs/talos` provider). There is nothing for
  Ansible to SSH into.
- **Hardened by design.** RBAC, API audit logging, anonymous-auth-off,
  secrets-encrypted-at-rest, profiling-off, and a KSPP kernel baseline
  are defaults, not add-ons.

The lab today provisions Ubuntu VMs intended to become a k3s cluster
(`environments/lab` names them `k3s-server`/`k3s-agent`). Talos is a
materially more secure and more reproducible substrate for that
Kubernetes layer.

## Decision

**Adopt Talos Linux as a first-class, additive Kubernetes substrate,
coexisting with the existing libvirt/Ubuntu stack.** It does not replace
`modules/libvirt-vm`; it sits alongside it for the Kubernetes use case.

Concretely:

1. New module **`modules/talos-cluster`** provisions a Talos cluster on
   libvirt: it creates the VMs with `dmacvicar/libvirt` (a dedicated NAT
   network with static DHCP reservations, a shared Talos base image,
   per-node overlay volumes, and per-node domains that boot the Talos
   image directly — **no cloud-init**) and drives the cluster with the
   `siderolabs/talos` provider (`talos_machine_secrets`,
   `data.talos_machine_configuration`, `talos_machine_configuration_apply`,
   `talos_machine_bootstrap`, `talos_cluster_kubeconfig`,
   `data.talos_client_configuration`).
2. New environment **`environments/talos-lab`** instantiates it (1
   control-plane + 2 workers by default) on a local backend.
3. The provider pin, the hardened machine-config baseline + secret
   handling, are decided in the companion ADRs
   [ADR-0014](0014-pin-siderolabs-talos-provider.md) and
   [ADR-0015](0015-talos-machineconfig-as-code-and-secrets.md).

**The Talos subsystem is intentionally NOT Ansible-managed.** There is
no host to SSH into; configuration *is* the machine config, applied as
code. This is a deliberate, documented exception to the infra ↔
config-management split that governs the Ubuntu stack. The split still
holds for Ubuntu VMs (`modules/libvirt-vm` + `automation`); Talos simply
has no config-management layer to delegate to.

Static IPs are assigned to every node (DHCP reservations on the
module-created network, pinned on each domain interface) so the Talos
API endpoints are known *before* configuration is applied — avoiding a
DHCP-lease chicken-and-egg with `talos_machine_configuration_apply`.

## Consequences

**Positive**

- A hardened-by-design, immutable, reproducible Kubernetes substrate:
  no SSH/shell/PAM attack surface, declarative config, RBAC + audit +
  at-rest encryption on by default.
- The cluster is fully described in OpenTofu: VMs *and* machine config
  *and* bootstrap *and* the exported kube/talos configs, in one
  `tofu apply`.
- Config-as-code hardening (ADR-0015) is regression-gated by the
  module's mock-provider tests, with no live cluster needed for CI.

**Negative**

- A second provider (`siderolabs/talos`, pre-1.0) enters the repo, with
  its own pin and upgrade cadence (ADR-0014).
- Talos's secrets (`talos_machine_secrets`) now live in OpenTofu state,
  which raises the bar on backend security for any non-lab Talos
  environment (ADR-0015 → ADR-0011 remote encrypted backend).
- Two operating models now coexist (Ansible-managed Ubuntu vs.
  API-managed Talos); contributors must know which path a given workload
  is on. Documented in the README and `CLAUDE.md`.
- Real validation needs a libvirtd host + `talosctl`; CI proves config
  generation and graph shape only. The "needs a real host/cluster"
  checklist is in the module README and the env README.

## Alternatives considered

- **k3s on Ubuntu (the current lab intent).** Keeps a single OS model
  and the Ansible split, but carries the full Ubuntu attack surface
  (SSH, shell, packages) on every node and relies on downstream
  hardening. Rejected for the Kubernetes layer in favour of Talos's
  hardened-by-design posture. The Ubuntu stack remains for non-Kubernetes
  hosts.
- **Managed Kubernetes (cloud).** Out of scope for the on-prem
  libvirt-centric design of this repo.

## References

- [ADR-0004 — Cloud-init bootstrap conventions](0004-cloud-init-bootstrap-conventions.md)
- [ADR-0014 — Pin `siderolabs/talos` provider](0014-pin-siderolabs-talos-provider.md)
- [ADR-0015 — Talos machine-config-as-code + secret handling](0015-talos-machineconfig-as-code-and-secrets.md)
- [Talos Linux documentation](https://docs.siderolabs.com/)
- [`siderolabs/talos` provider](https://registry.terraform.io/providers/siderolabs/talos/latest/docs)
- `modules/talos-cluster/`, `environments/talos-lab/`, `docs/talos-cis-kubernetes.md`
