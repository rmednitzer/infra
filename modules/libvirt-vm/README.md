# libvirt-vm Module

Provisions a KVM/libvirt virtual machine using the [`dmacvicar/libvirt`](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs) provider. Supports cloud-init user-data injection, optional additional data disks, and configurable CPU, memory, and disk resources.

## Requirements

- A running libvirt/KVM host accessible via the provider's `uri`
- A cloud-init compatible base image (e.g., Ubuntu 24.04 cloud image)
- An existing libvirt network

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
| `vcpus` | `number` | `2` | Number of virtual CPUs (≥ 1) |
| `memory_mib` | `number` | `2048` | Memory in MiB (≥ 512) |
| `disk_size_gib` | `number` | `20` | Root disk size in GiB (≥ 1, and ≥ base image virtual size) |
| `base_image` | `string` | — | Path or URL to cloud-init compatible base image |
| `network_name` | `string` | `"default"` | Libvirt network name |
| `storage_pool` | `string` | `"default"` | Libvirt storage pool for volumes and cloud-init disk |
| `ssh_public_key` | `string` | — | SSH public key for cloud-init injection (sensitive, validated) |
| `additional_disks` | `list(object({name, size_gib}))` | `[]` | Optional additional data disks (unique names, size ≥ 1 GiB) |
| `autostart` | `bool` | `true` | Start VM on host boot |
| `wait_for_lease` | `bool` | `true` | Wait for a DHCP lease before completing apply; set `false` for bridged/macvtap networks |

## Outputs

| Name | Description |
|------|-------------|
| `vm_id` | Libvirt domain ID |
| `vm_name` | Libvirt domain name |
| `ip_address` | VM IP address (from DHCP lease), or `null` if no lease is available |
| `mac_address` | VM MAC address, or `null` if unavailable |

## Cloud-Init

The module injects a `cloud_init.cfg` template that:
- Sets the VM hostname
- Adds the provided SSH public key for the `ubuntu` user
- Locks the `ubuntu` user password (`lock_passwd: true`) and disables password
  authentication (`ssh_pwauth: false`) and root login (`disable_root: true`)
- Runs `package_update` on first boot
- Installs and enables `qemu-guest-agent` (the domain sets `qemu_agent = true`
  so libvirt can report guest addresses via the agent)

## Notes

- The base image is cloned into a per-VM backing volume; the root disk is a
  thin-provisioned overlay on top of it. Because the backing volume is created
  per module instance (named `<vm_name>-base.qcow2`), provisioning N VMs from
  the same image creates N copies. For large fleets, consider managing a single
  shared base volume outside this module and referencing it.
- `disk_size_gib` must be **greater than or equal to** the virtual size of
  `base_image`. A smaller value fails at apply time with a libvirt volume
  error, since the root overlay cannot be smaller than its backing store.
- Additional disks are created as separate volumes and attached after the root
  disk in deterministic (sorted-by-name) order.
- `wait_for_lease = true` (default) makes `ip_address` reliable on libvirt NAT
  networks. On bridged or macvtap networks the libvirt host cannot observe the
  guest's DHCP lease, so apply would hang — set `wait_for_lease = false` there
  and obtain the address out of band (e.g., via the guest agent).
