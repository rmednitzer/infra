# `libvirt-vm` module

KVM/libvirt VM provisioning with cloud-init via
[`dmacvicar/libvirt`](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs).
Supports cloud-init user-data injection, optional additional data
disks, and configurable CPU, memory, and disk resources.

Provider pin: `~> 0.8.0`
([ADR-0002](../../docs/adr/0002-pin-libvirt-provider-to-0.8.md)).
Cloud-init defaults:
[ADR-0004](../../docs/adr/0004-cloud-init-bootstrap-conventions.md).

## Requirements

- A running libvirt/KVM host accessible via the provider's `uri`
- A cloud-init compatible base image (e.g. Ubuntu 24.04 noble cloud
  image)
- An existing libvirt **network** named by `var.network_name`
  (default: `default`) — the module does not create the network
- An existing libvirt **storage pool** named by `var.storage_pool`
  (default: `default`) — the module does not create the pool

## Usage

```hcl
module "k3s_server" {
  source = "../../modules/libvirt-vm"

  vm_name        = "k3s-server-01"
  vcpus          = 2
  memory_mib     = 4096
  disk_size_gib  = 30
  base_image     = var.base_image_path
  network_name   = "default"
  ssh_public_key = var.ssh_public_key
}
```

## Inputs

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `vm_name` | `string` | — | VM hostname (validated as an RFC 1123 label) |
| `vcpus` | `number` | `2` | Virtual CPU count (≥ 1) |
| `memory_mib` | `number` | `2048` | Memory in MiB (≥ 512) |
| `disk_size_gib` | `number` | `20` | Root disk size in GiB (≥ 1, and ≥ base image virtual size) |
| `base_image` | `string` | — | Path or URL to a cloud-init compatible base image |
| `network_name` | `string` | `"default"` | Libvirt network name |
| `storage_pool` | `string` | `"default"` | Libvirt storage pool for volumes and the cloud-init disk |
| `ssh_public_key` | `string` | — | SSH public key for cloud-init injection (sensitive, validated) |
| `additional_disks` | `list(object({name, size_gib}))` | `[]` | Optional additional data disks (unique names, size ≥ 1 GiB) |
| `autostart` | `bool` | `true` | Start VM on host boot |
| `wait_for_lease` | `bool` | `true` | Wait for a DHCP lease before completing apply; set `false` for bridged/macvtap networks |

## Outputs

| Name | Description |
|------|-------------|
| `vm_id` | Libvirt domain ID |
| `vm_name` | Libvirt domain name |
| `ip_address` | VM IP address from DHCP lease, or `null` if no lease is available |
| `mac_address` | VM MAC address, or `null` if unavailable |

## Console and graphics

The domain ships with a `console { type = "pty" target_type = "serial" }`
block (so `virsh console <vm>` works) and **no** `graphics` block.
SPICE and VNC listeners are intentionally omitted. Rationale, threat
model, and operator note in
[ADR-0008](../../docs/adr/0008-omit-graphics-from-libvirt-domain-by-default.md).
Operators who need graphical access for a specific VM should fork
the module or thread a `graphics` input through.

## Cloud-init

The shipped `cloud_init.cfg`:

- Sets the VM hostname
- Adds the provided SSH public key to the `ubuntu` user
- Locks the `ubuntu` user password (`lock_passwd: true`), disables
  password authentication (`ssh_pwauth: false`) and root login
  (`disable_root: true`)
- Runs `package_update` on first boot (no upgrade — operator action)
- Installs and enables `qemu-guest-agent` (the domain sets
  `qemu_agent = true` so libvirt can report guest addresses via the
  agent)

## Notes

- The base image is cloned into a per-VM backing volume; the root disk
  is a thin-provisioned overlay on top of it. Because the backing
  volume is created per module instance (named `<vm_name>-base.qcow2`),
  provisioning N VMs from the same image creates N copies. For large
  fleets, manage a single shared base volume outside this module and
  reference it.
- `disk_size_gib` must be **≥ the virtual size of `base_image`**. A
  smaller value fails at apply with a libvirt volume error; the root
  overlay cannot be smaller than its backing store.
- Additional disks are created as separate volumes and attached after
  the root disk in deterministic (sorted-by-name) order.
- `wait_for_lease = true` (default) makes `ip_address` reliable on
  libvirt NAT networks. On bridged or macvtap networks, the libvirt
  host cannot observe the guest's DHCP lease, so apply would hang —
  set `wait_for_lease = false` and obtain the address out of band
  (e.g. via the guest agent).
- `var.storage_pool` and `var.network_name` must point at libvirt
  resources that already exist on the host. Creating them is outside
  the module's scope; on a fresh libvirtd install, `virsh pool-list
  --all` and `virsh net-list --all` should show the defaults.
- The module sets `meta_data` on `libvirt_cloudinit_disk` to
  `instance-id: ${vm_name}\nlocal-hostname: ${vm_name}\n`, satisfying
  the cloud-init NoCloud contract for `instance-id` deterministically
  from `var.vm_name`. See
  [ADR-0007](../../docs/adr/0007-set-meta-data-on-libvirt-cloudinit-disk.md)
  for the rationale and migration note. Operators on existing infra
  see a one-time `libvirt_cloudinit_disk` re-create + domain restart
  on the first apply after upgrading past this change.
