# `talos-cluster` module

Provisions a [Talos Linux](https://www.talos.dev/) Kubernetes cluster on
KVM/libvirt. It creates the VMs with
[`dmacvicar/libvirt`](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs)
and drives the cluster with the partner-verified
[`siderolabs/talos`](https://registry.terraform.io/providers/siderolabs/talos/latest/docs)
provider: machine secrets, machine configuration (with a hardened,
config-as-code baseline), config apply over the Talos API, etcd
bootstrap, and the exported `kubeconfig` / `talosconfig`.

Talos is **API-only and immutable** — no SSH, no shell, no PAM, no
package manager. It is configured exclusively by a declarative machine
configuration applied over its API. This module is therefore
**intentionally not Ansible-managed**: there is no host to configure.
That is a deliberate split from `modules/libvirt-vm` (Ubuntu +
cloud-init + downstream Ansible). See
[ADR-0013](../../docs/adr/0013-adopt-talos-linux.md).

Provider pins: libvirt `~> 0.9.0`
([ADR-0002](../../docs/adr/0002-pin-libvirt-provider-to-0.8.md) pin rule; bumped
0.8→0.9 in [ADR-0016](../../docs/adr/0016-migrate-libvirt-provider-to-0.9.md)),
talos `~> 0.11.0` ([ADR-0014](../../docs/adr/0014-pin-siderolabs-talos-provider.md)).
Hardening baseline + secret handling:
[ADR-0015](../../docs/adr/0015-talos-machineconfig-as-code-and-secrets.md).
CIS Kubernetes mapping: [`docs/talos-cis-kubernetes.md`](../../docs/talos-cis-kubernetes.md).

## How it works

```
talos_machine_secrets ──► data.talos_machine_configuration {controlplane,worker}
                                     │  (+ hardening config_patches)
libvirt_network (static DHCP)        ▼
libvirt_volume.talos_base ──► libvirt_volume.root[*] ──► libvirt_domain.node[*]
                                     │  (boot Talos image, maintenance mode)
                                     ▼
                      talos_machine_configuration_apply.node[*]
                                     ▼
                      talos_machine_bootstrap (first control plane)
                                     ▼
              talos_cluster_kubeconfig  +  data.talos_client_configuration
                    (kubeconfig)              (talosconfig)
```

Nodes get **static IPs** via libvirt-native **MAC→IP DHCP reservations**
(`ips[].dhcp.hosts` entries) on the module-created NAT network. dmacvicar/libvirt
0.9.x exposes these reservations as a native HCL attribute, so the module
declares them directly (ADR-0016 — this replaced the 0.8.x XSLT-on-XML hack the
module previously needed); the `dns` hosts add matching DNS A records but do
**not**, on their own, pin the lease. This is what makes each Talos API endpoint
known *before* any configuration is applied — avoiding a DHCP-lease
chicken-and-egg with `talos_machine_configuration_apply`, which targets each
node at its declared IP.

## Requirements

- OpenTofu **≥ 1.10** (`versions.tf`).
- A running libvirt/KVM host accessible via the provider's `uri`, with
  the named `storage_pool` already present.
- A **Talos disk image** (nocloud/metal qcow2 or raw) for the target
  version/arch, from the Talos image factory
  ([factory.talos.dev](https://factory.talos.dev/)). Set it via
  `var.talos_image`, and set `var.talos_image_format` to match its
  format (`qcow2` default, or `raw`) so libvirt/qemu reads the source
  correctly.
- The control-plane and worker node IPs must be free on the
  module-created `10.5.0.0/24` NAT network (or override the network
  layout downstream).

## Usage

```hcl
module "talos" {
  source = "../../modules/talos-cluster"

  cluster_name     = "lab-talos"
  cluster_endpoint = "https://10.5.0.10:6443"
  talos_image      = var.talos_image

  control_plane_nodes = {
    cp-01 = { ip = "10.5.0.10", mac = "52:54:00:00:00:10" }
  }
  worker_nodes = {
    work-01 = { ip = "10.5.0.20", mac = "52:54:00:00:00:20" }
    work-02 = { ip = "10.5.0.21", mac = "52:54:00:00:00:21" }
  }
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `cluster_name` | `string` | — | Cluster name (RFC 1123 label); domain prefix + Talos cluster name |
| `cluster_endpoint` | `string` | — | Kubernetes API endpoint URL, e.g. `https://10.5.0.10:6443` |
| `talos_image` | `string` | — | Path/URL to the Talos disk image (boot disk for every node) |
| `talos_image_format` | `string` | `"qcow2"` | Disk-image format of `talos_image` (`qcow2` or `raw`); must match the actual on-disk format |
| `talos_version` | `string` | `v1.10.5` | Talos version contract for secrets/config generation |
| `kubernetes_version` | `string` | `1.32.3` | Kubernetes version Talos installs (no leading `v`) |
| `control_plane_nodes` | `map(object)` | — | Control-plane node name → `{ip, mac, vcpus?, memory_mib?, disk_gib?}`; odd count |
| `worker_nodes` | `map(object)` | `{}` | Worker node name → `{ip, mac, vcpus?, memory_mib?, disk_gib?}` |
| `network_cidr` | `string` | `"10.5.0.0/24"` | IPv4 CIDR for the module-created `<cluster_name>-net` NAT network; node IPs must fall in it |
| `storage_pool` | `string` | `"default"` | Libvirt storage pool for the base + per-node volumes |
| `install_disk` | `string` | `/dev/vda` | Block device Talos installs onto (match the virtio bus) |
| `time_servers` | `list(string)` | `["time.cloudflare.com"]` | NTP servers (`machine.time.servers`) |
| `registry_mirrors` | `map(list(string))` | `{}` | Registry host → mirror endpoints (`machine.registries.mirrors`) |
| `pod_security_enforce_profile` | `string` | `"restricted"` | Cluster-wide PSA enforce profile (Talos default is the looser `baseline`) |
| `pod_security_exempt_namespaces` | `list(string)` | `["kube-system"]` | Namespaces exempt from PSA enforcement |
| `extra_control_plane_config_patches` | `list(string)` | `[]` | Caller patches merged after the hardening baseline (control plane) |
| `extra_worker_config_patches` | `list(string)` | `[]` | Caller patches merged after the hardening baseline (workers) |
| `apply_mode` | `string` | `"auto"` | `talos_machine_configuration_apply` mode |

## Outputs

| Name | Description |
|------|-------------|
| `kubeconfig` | Raw kubeconfig YAML (**sensitive**) |
| `talosconfig` | Raw talosconfig YAML for talosctl (**sensitive**) |
| `cluster_endpoint` | The configured Kubernetes API endpoint |
| `control_plane_node_ips` | Map of control-plane node name → IP |
| `worker_node_ips` | Map of worker node name → IP |
| `node_ips` | Map of every node name → IP |
| `bootstrap_node_ip` | IP of the bootstrapped control-plane node |
| `machine_secrets_id` | Non-sensitive handle for the cluster's machine secrets |

## Hardening baseline (config-as-code)

`machineconfig/common.yaml.tftpl` (every node) and
`machineconfig/controlplane.yaml.tftpl` (control plane) are rendered and
threaded into the machine configuration via `config_patches`. They layer
the following on top of Talos's already-hardened defaults:

- **Pod Security Admission** — `enforce: restricted` (Talos default is
  `baseline`), `audit`/`warn: restricted`, system-namespace exemptions.
- **Kubernetes API audit logging** — explicit `audit.k8s.io/v1` policy.
  First-match-wins ordering: `RequestResponse` for secrets/configmaps/RBAC
  (incl. their reads) precedes the broad read-noise `None` rule, then
  `Metadata` elsewhere.
- **API server hardening** — profiling disabled, anonymous auth off
  (asserts Talos defaults as config-as-code).
- **KSPP sysctls** — `kptr_restrict`, `dmesg_restrict`,
  `unprivileged_bpf_disabled`, BPF JIT hardening, reverse-path filtering,
  redirect/source-route hardening, martian logging.
- **Kubelet hardening** — anonymous auth off, webhook authz, TLS 1.3,
  `podPidsLimit`.
- **Features** — Talos `rbac`, KubePrism, host DNS.
- **Time** — NTP from `var.time_servers`.
- **Registries** — optional pull-through mirrors.
- **Install disk** — explicit `machine.install.disk`.

Caller patches (`extra_*_config_patches`) are appended **after** the
baseline so they can override it.

## Secrets

`talos_machine_secrets` (the cluster CA + bootstrap token) lives in
**state**. Any environment that uses this module **must** use an
encrypted remote backend (ADR-0015). `kubeconfig` and `talosconfig`
outputs are `sensitive = true`; consuming environments must keep the
written files out of git (see `environments/talos-lab/.gitignore`).

## Tests

Native OpenTofu tests in [`tests/`](tests/) mock **both** providers
(`mock_provider "libvirt"`, `mock_provider "talos"`), so they need **no
libvirtd, no talosctl, and no cluster**:

```bash
tofu init -backend=false
tofu test
```

- `tests/validation.tftest.hcl` — every input validation rejects bad
  input at plan time (bad cluster name/endpoint, non-semver versions,
  even control-plane count, non-RFC-1123 node keys, malformed/out-of-range
  IP/MAC, sub-floor VM sizing, bad install disk, unknown PSA profile /
  apply mode), plus the cross-variable `node_invariants` preconditions
  (disjoint control-plane/worker names, unique node IPs, unique node MACs,
  IPs inside `network_cidr` and not its network/gateway/broadcast address).
- `tests/module.tftest.hcl` — node-count → resource fan-out, bootstrap
  targeting, the derived Kubernetes minor, static-IP wiring, the native
  DHCP reservations (one `ips[].dhcp.hosts` entry per node), the `on_destroy`
  reset default (off), config-patch ordering, and the PSA / audit / KSPP-sysctl /
  kubelet hardening invariants in the rendered patches.

## What needs a real host/cluster to validate

The mock tests prove config generation and resource graph shape. They do
**not** boot Talos. Before trusting this in anger, on a real libvirtd
host with `talosctl` available:

- Confirm Talos boots from the chosen image and enters maintenance mode,
  and that `talos_machine_configuration_apply` reaches it at the static
  IP — i.e. the native `ips[].dhcp.hosts` reservations actually pin each
  MAC to its declared IP (the reservations are unit-checked in the mock
  suite, but only a real libvirtd proves dnsmasq honours them). The 0.9.x
  schema migration itself was host-verified by the maintainer (ADR-0016);
  this list is the per-deployment validation any new cluster still warrants.
- Decide node scale-down policy: `on_destroy.reset` defaults to **off** (a
  removed node's VM is deleted but it is *not* reset, leaving stale etcd /
  Kubernetes membership). Flip `reset = true` in `main.tf` for clean
  scale-down of a healthy cluster — but never for removing an already-dead
  node (a graceful etcd-leave reset blocks `tofu destroy`); reset those out
  of band (`runbooks/talos/reset-node.sh`) first.
- Confirm the install disk (`/dev/vda`) matches what Talos sees on the
  virtio bus.
- Confirm `talos_machine_bootstrap` brings up etcd and the API server,
  and that `kubeconfig` reaches a healthy cluster.
- Run `kube-bench` / a CIS-Kubernetes scan and reconcile against
  [`docs/talos-cis-kubernetes.md`](../../docs/talos-cis-kubernetes.md)
  (expect the documented architectural false positives).
- Verify the `restricted` PSA profile does not break the CNI/CSI you
  deploy; adjust `pod_security_exempt_namespaces` if needed.

## Notes

- The module creates its **own** NAT network (`<cluster_name>-net`,
  `var.network_cidr`, default `10.5.0.0/24`) so the static IP↔MAC
  reservations are guaranteed. This differs from `modules/libvirt-vm`,
  which attaches to a pre-existing network.
- No QEMU guest-agent channel on the domains: Talos does not run the QEMU
  guest agent (no general-purpose userspace), so the module omits it (0.8.x:
  `qemu_agent = false`).
- The 0.9.x libvirt migration landed in
  [ADR-0016](../../docs/adr/0016-migrate-libvirt-provider-to-0.9.md), which
  moved this module and `libvirt-vm` together (they shared the 0.8.x surface).
  Accepted after host verification.
