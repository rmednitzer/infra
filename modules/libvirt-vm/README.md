# `libvirt-vm` module

KVM/libvirt VM provisioning with cloud-init via
[`dmacvicar/libvirt`](https://registry.terraform.io/providers/dmacvicar/libvirt/latest/docs).
Supports cloud-init user-data injection, optional additional data
disks, and configurable CPU, memory, and disk resources.

Provider pin: `~> 0.9.0`
([ADR-0002](../../docs/adr/0002-pin-libvirt-provider-to-0.8.md) pin rule;
bumped 0.8→0.9 in
[ADR-0016](../../docs/adr/0016-migrate-libvirt-provider-to-0.9.md) — **Proposed,
merge gated on host verification**). Cloud-init defaults:
[ADR-0004](../../docs/adr/0004-cloud-init-bootstrap-conventions.md).

## Requirements

- OpenTofu **≥ 1.10** (`versions.tf`). The floor is aligned with the
  production `use_lockfile = true` target
  ([ADR-0003](../../docs/adr/0003-state-backend-strategy.md)) and is the
  oldest version CI exercises in practice; CI runs `1.12`
  ([`.opentofu-version`](../../.opentofu-version)).
- A running libvirt/KVM host accessible via the provider's `uri`
- A cloud-init compatible base image. The `base_image` input is
  version-neutral — both Ubuntu 24.04 LTS (noble,
  `cloud-images.ubuntu.com/noble/`) and Ubuntu 26.04 LTS (resolute,
  kernel 7.0, `cloud-images.ubuntu.com/resolute/`) work. The shipped
  `cloud_init.cfg` is distro-neutral: netplan and cloud-init behaviour
  is unchanged across the two LTS releases, so no template edit is
  needed to switch. The only caveat is the image *path/URL* itself
  (set via `var.base_image`); the secure cloud-init defaults are
  identical.
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
| `base_image` | `string` | — | Path or URL to a cloud-init compatible base image (version-neutral: Ubuntu 24.04 noble or 26.04 resolute) |
| `network_name` | `string` | `"default"` | Libvirt network name |
| `storage_pool` | `string` | `"default"` | Libvirt storage pool for volumes and the cloud-init disk |
| `ssh_public_key` | `string` | — | SSH public key for cloud-init injection (sensitive, validated) |
| `additional_disks` | `list(object({name, size_gib}))` | `[]` | Optional additional data disks (unique names, size ≥ 1 GiB) |
| `autostart` | `bool` | `true` | Start VM on host boot |
| `graphics` | `object({type, listen_address?, autoport?})` | `null` | Optional graphics device. `null` omits graphics entirely (secure default, ADR-0008); set it only for VMs that need a SPICE/VNC console |

## Outputs

| Name | Description |
|------|-------------|
| `vm_id` | Libvirt domain ID |
| `vm_name` | Libvirt domain name |
| `ip_address` | VM IP address from DHCP lease, or `null` if no lease is available |
| `mac_address` | VM MAC address, or `null` if unavailable |
| `data_disk_ids` | Map of `additional_disks` name to libvirt volume ID (empty when none configured) |
| `cloudinit_disk_id` | Libvirt volume ID of the cloud-init NoCloud disk |

## Console and graphics

The domain ships with a serial console (`devices.serials` + a matching
`devices.consoles` aliased to it, so `virsh console <vm>` works) and **no**
graphics device by default. SPICE and VNC listeners are intentionally omitted.
Rationale, threat model, and operator note in
[ADR-0008](../../docs/adr/0008-omit-graphics-from-libvirt-domain-by-default.md).

Operators who need graphical access for a specific VM set the optional
`graphics` input rather than forking the module — the secure
no-listener default holds whenever `graphics` is left `null`:

```hcl
module "workstation" {
  source = "../../modules/libvirt-vm"
  # ... required inputs ...

  graphics = {
    type           = "spice"
    listen_address = "127.0.0.1" # keep the listener host-local
  }
}
```

## Cloud-init

The shipped `cloud_init.cfg`:

- Sets the VM hostname
- Adds the provided SSH public key to the `ubuntu` user
- Locks the `ubuntu` user password (`lock_passwd: true`), disables
  password authentication (`ssh_pwauth: false`) and root login
  (`disable_root: true`)
- Runs `package_update` on first boot (no upgrade — operator action)
- Installs and enables `qemu-guest-agent` (the domain attaches an
  `org.qemu.guest_agent.0` virtio channel — the 0.9.x equivalent of 0.8.x's
  `qemu_agent = true` — so libvirt can report guest state)

## Tests

Native OpenTofu tests live in [`tests/`](tests/) and mock the libvirt
provider (`mock_provider "libvirt"`), so they need **no libvirtd**:

```bash
tofu init -backend=false
tofu test
```

- `tests/validation.tftest.hcl` — every input validation rejects bad
  input at plan time (bad hostnames, malformed/empty `ssh_public_key`,
  sub-floor `memory_mib`, duplicate `additional_disks` names).
- `tests/module.tftest.hcl` — positive assertions: the deterministic
  NoCloud meta-data ([ADR-0007](../../docs/adr/0007-set-meta-data-on-libvirt-cloudinit-disk.md)),
  GiB-to-byte disk math, one volume per additional disk, the ADR-0004
  cloud-init security invariants (`ssh_pwauth: false`,
  `disable_root: true`, `lock_passwd: true`), and the `graphics` default
  /override behaviour. CI runs the suite as the `Module Tests` job.

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
  the root disk (vda) as vdb, vdc, … in declared `additional_disks`
  list order, with the cloud-init CD-ROM last. The module
  **provisions and attaches** the raw block devices only — partitioning,
  formatting (`mkfs`), and mounting are the **configuration-management
  (Ansible) layer's** responsibility, consistent with the
  infra/config-management split in
  [ADR-0004](../../docs/adr/0004-cloud-init-bootstrap-conventions.md).
  No `fs_setup`/`mounts` directives are injected into cloud-init. The
  `data_disk_ids` output exposes each volume's libvirt ID so the
  downstream layer can map names to devices.
- `ip_address`/`mac_address` are read via the
  `libvirt_domain_interface_addresses` data source (`source = "lease"`), since
  libvirt 0.9.x dropped 0.8.x's `wait_for_lease` / `network_interface[].addresses`
  surface (ADR-0016). The address only becomes known once the guest boots and
  acquires a DHCP lease, so `ip_address` may be `null` on the first apply and
  populate on a subsequent refresh/apply — a behaviour change from 0.8.x's
  blocking `wait_for_lease` that is flagged for host verification in ADR-0016.
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
