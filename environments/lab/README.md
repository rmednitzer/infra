# `lab` environment

Development and testing on a local KVM host with **local state**. Not
for production. Backend decision: [ADR-0003](../../docs/adr/0003-state-backend-strategy.md).

## Prerequisites

- A local KVM host with `libvirtd` running, the `default` storage pool
  and `default` network defined (see
  [ADR-0006 Finding 7](../../docs/adr/0006-code-audit-2026-05.md)).
- A cloud-init compatible base image accessible to `libvirtd` (Ubuntu
  24.04 noble by default).
- An SSH key pair for VM access.
- OpenTofu 1.6+ (1.12.0 pinned via [`.opentofu-version`](../../.opentofu-version)).

## Usage

```bash
cd environments/lab
export TF_VAR_ssh_public_key="$(cat ~/.ssh/id_ed25519.pub)"
tofu init && tofu plan && tofu apply
```

Lab-specific defaults: [`terraform.tfvars`](./terraform.tfvars) (non-secret
only). Module API: [`../../modules/libvirt-vm/README.md`](../../modules/libvirt-vm/README.md).

## Secrets and state

`TF_VAR_*` environment variables only. Never commit secrets to
`terraform.tfvars`. Do not share `terraform.tfstate` — it contains
resource IDs and potentially sensitive metadata. Lab state is not
promoted to production (separate backend, separate state).
