# `talos-lab` environment

A single-operator lab [Talos Linux](https://www.talos.dev/) Kubernetes
cluster on local KVM/libvirt, built with the
[`talos-cluster`](../../modules/talos-cluster/) module. Local backend,
reproducible from this configuration.

Default topology: **1 control-plane + 2 workers**. Talos is API-only and
immutable — this environment is **intentionally not Ansible-managed**
(there is no host to configure). See
[ADR-0013](../../docs/adr/0013-adopt-talos-linux.md).

## Prerequisites

- A KVM/libvirt host with `libvirtd` running and the `default` storage
  pool present.
- A **Talos disk image** for the target version/arch from the Talos
  image factory ([factory.talos.dev](https://factory.talos.dev/)). Point
  `talos_image` (in [`terraform.tfvars`](./terraform.tfvars)) at it, and
  set `talos_image_format` (`qcow2` default, or `raw`) to match it.
- The IPs in `control_plane_nodes` / `worker_nodes` must be free on the
  module-created `10.5.0.0/24` NAT network.
- `talosctl` and `kubectl` on the operator workstation to use the
  cluster (not required to apply).

## Apply

```bash
cd environments/talos-lab
tofu init
tofu plan
tofu apply
```

Then export the credentials (sensitive outputs — written files are
gitignored):

```bash
tofu output -raw kubeconfig  > kubeconfig
tofu output -raw talosconfig > talosconfig
export KUBECONFIG="$PWD/kubeconfig"
export TALOSCONFIG="$PWD/talosconfig"
kubectl get nodes
talosctl -n 10.5.0.10 health
```

## State and secrets

- **Local backend** (`backend.tf`), acceptable for a single operator
  (ADR-0003). The state contains `talos_machine_secrets` (the cluster CA
  + bootstrap token); the state file is gitignored by the root
  `.gitignore`. The per-node apply/bootstrap resources pass their secrets
  through write-only (`_wo`) arguments, so the rendered machine config and
  client credentials are not duplicated per node in state (ADR-0017;
  needs OpenTofu ≥ 1.11).
- `kubeconfig` / `talosconfig` outputs are `sensitive = true`. The files
  you write from them are gitignored by this directory's
  [`.gitignore`](./.gitignore).
- A **production** Talos cluster must use the encrypted remote backend
  (ADR-0011 / ADR-0015), never a local backend.

## What needs a real host/cluster

This configuration validates and tests (via the module's mock-provider
suite) without any backend. **Actually applying it needs a real libvirtd
host and `talosctl`.** It has not been booted in CI. The module README's
["What needs a real host/cluster to validate"](../../modules/talos-cluster/README.md#what-needs-a-real-hostcluster-to-validate)
section lists the post-apply checks (Talos boot + maintenance mode,
install-disk match, etcd bootstrap, CIS-Kubernetes scan, PSA-vs-CNI
compatibility).

## Hardening

The module applies a hardened, config-as-code baseline (Pod Security
Admission `restricted`, API audit logging, KSPP sysctls, kubelet
hardening) on top of Talos's hardened defaults. Mapping to the CIS
Kubernetes Benchmark: [`docs/talos-cis-kubernetes.md`](../../docs/talos-cis-kubernetes.md).
