# ADR-0016: Migrate `dmacvicar/libvirt` to `~> 0.9.0`

- **Status**: Accepted
- **Date**: 2026-06-04

> **Status note (2026-06-04):** Accepted after the maintainer ran the
> [ADR-0009](0009-begin-libvirt-0.9-migration-evaluation.md) host-verification
> gates on a real libvirtd lab host (see *Host verification* below). This ADR
> **supersedes** the migration plan and `~> 0.8.0` pin in
> [ADR-0002](0002-pin-libvirt-provider-to-0.8.md), concludes the ADR-0009
> evaluation, and absorbs the [ADR-0012](0012-libvirt-0.9-schema-diff-inventory.md)
> schema-diff inventory (all three are now *Superseded by ADR-0016*). The
> pre-1.0 patch-pin discipline ADR-0002 established remains in force — now at
> `~> 0.9.0`.

## Context

[ADR-0002](0002-pin-libvirt-provider-to-0.8.md) pinned `dmacvicar/libvirt` to
`~> 0.8.0`. [ADR-0009](0009-begin-libvirt-0.9-migration-evaluation.md) opened a
structured 0.8.x → 0.9.x evaluation with four host gates plus a schema-diff
inventory; [ADR-0012](0012-libvirt-0.9-schema-diff-inventory.md) recorded the
inventory as a **desk exercise**, explicitly "documentation-sourced, not
host-verified … must be re-checked on a real 0.9.x install."

0.9.0 is a ground-up rewrite on the Terraform Plugin Framework that "breaks
compatibility" and models the libvirt XML tree directly rather than offering
0.8.x's cloud-like abstractions. As of this ADR the release lines are:

| Branch | Latest | Notes |
|--------|--------|-------|
| 0.8.x | 0.8.3 (Mar 2024) | Original SDKv2 architecture; bugfix-only |
| 0.9.x | **0.9.8** (May 2026) | Plugin-framework rewrite; schema-breaking; actively developed |

This ADR was prepared against the **real provider**: the `dmacvicar/libvirt`
v0.9.8 docs and examples (cloned at the tag), with both modules re-shaped to the
0.9.x schema and exercised through `tofu validate` and the `tofu test`
mock-provider suites on **OpenTofu 1.12.1 with the actual v0.9.8 plugin
installed** (the plugin loads its schema without a libvirtd connection, so
schema-level validation is real even without a host). This upgrades the
ADR-0012 deltas from "to be confirmed" to "confirmed against the 0.9.8 schema" —
but schema-correct is not the same as host-correct (see Host verification).

The Talos provider is **unaffected** and stays `~> 0.11.0`
([ADR-0014](0014-pin-siderolabs-talos-provider.md)). Both modules consume the
libvirt provider, so per ADR-0012 they move together; only the `libvirt` pin
changes.

## Decision

Bump `dmacvicar/libvirt` to **`~> 0.9.0`** in `modules/libvirt-vm`,
`modules/talos-cluster`, and all three environment roots (`lab`, `talos-lab`,
`production`), and adapt every resource to the 0.9.x schema. Refresh all five
`.terraform.lock.hcl` files to v0.9.8 with multi-platform hashes
(`linux_amd64`, `linux_arm64`, `darwin_amd64`, `darwin_arm64`), matching the
ADR-0014 lock convention.

### Schema deltas applied (host-doc-verified against v0.9.8)

**`libvirt_volume`**

| 0.8.x | 0.9.x |
|-------|-------|
| `source = "<url/path>"` | `create = { content = { url = "<url/path>" } }` |
| `base_volume_id = <id>` | `backing_store = { path = <vol>.path, format = { type = "qcow2" } }` |
| `size = <bytes>` | `capacity = <bytes>` |
| `format = "qcow2"` | `target = { format = { type = "qcow2" } }` |

**`libvirt_domain`**

| 0.8.x | 0.9.x |
|-------|-------|
| (implicit) | `type = "kvm"` (required) + `os = { type = "hvm" }` |
| `memory = <MiB>` | `memory = <n>` **+ `memory_unit = "MiB"`** (0.9.x default unit is not MiB — silent under-allocation otherwise) |
| (started implicitly) | `running = true` |
| `disk { volume_id = … }` block | `devices.disks = [{ source = { volume = { pool, volume } }, target = { dev, bus }, driver = { type } }]` |
| `network_interface { network_name, wait_for_lease }` block | `devices.interfaces = [{ type = "network", model = { type = "virtio" }, source = { network = { network } }, mac = { address } }]` |
| `console { type, target_type="serial", target_port }` block | `devices.serials = [{ target = { port = 0 } }]` + `devices.consoles = [{ target = { type = "serial", port = 0 } }]` |
| `qemu_agent = true` | `devices.channels = [{ source = { unix = {} }, target = { virt_io = { name = "org.qemu.guest_agent.0" } } }]` |
| `graphics { type, listen_type, listen_address, autoport }` block | `devices.graphics = [{ vnc = { listen, auto_port } }]` (per-protocol `vnc {}`/`spice {}`) |
| `cloudinit = libvirt_cloudinit_disk.x.id` | ISO wrapped in a `libvirt_volume` from `libvirt_cloudinit_disk.x.path`, attached as a read-only `device = "cdrom"` disk |
| `libvirt_domain.x.network_interface[0].addresses[0]` | `data.libvirt_domain_interface_addresses` (`source = "lease"`) |

**`libvirt_cloudinit_disk`** — survives in 0.9.x (the ADR-0012 "highest-risk"
deprioritization did not remove it). Same `user_data` / `meta_data`
(ADR-0004/0007 baseline unchanged); it now only generates the ISO on disk
(exporting `.path`) and is no longer attached via a top-level `cloudinit`
argument. It no longer takes a `pool`; the ISO is uploaded into the pool via a
companion `libvirt_volume`.

**`libvirt_network`** (Talos module) — 0.9.x exposes **native DHCP host
reservations**, so the 0.8.x XSLT hack is **deleted**
(`network-dhcp-hosts.xslt.tftpl` removed):

| 0.8.x | 0.9.x |
|-------|-------|
| `mode = "nat"` | `forward = { mode = "nat" }` |
| `addresses = [cidr]` | `ips = [{ address = cidrhost(cidr,1), prefix = <n> }]` |
| `dhcp { enabled = true }` + `xml { xslt = … }` for `<host>` reservations | `ips[].dhcp = { hosts = [{ mac, ip, name }] }` (native) |
| `dns { enabled, hosts { hostname, ip } }` | `dns = { enable = "yes", host = [{ ip, hostnames = [{ hostname }] }] }` |
| `domain = "<x>.local"` | `domain = { name = "<x>.local" }` |

Module interface changes: `libvirt-vm` drops `var.wait_for_lease` (0.9.x has no
such interface flag) and reshapes `var.graphics` (drops `listen_type`).
`ip_address`/`mac_address` outputs now read from the interface-addresses data
source.

### Evidence (this branch)

- `tofu validate` clean on `environments/{lab,talos-lab,production}` against
  libvirt v0.9.8 (and talos v0.11.0).
- `tofu test` green: `libvirt-vm` 16/16, `talos-cluster` 45/45 (mock-provider
  suites, re-shaped to the 0.9.x attribute surface).
- `tofu fmt -recursive` clean; lock files refreshed multi-platform.

### Host verification (maintainer-attested, 2026-06-04)

`tofu validate`/`tofu test` (run in CI) prove the config matches the v0.9.8
*schema*; they do **not** prove libvirt accepts the generated XML or that guests
boot. The [ADR-0009](0009-begin-libvirt-0.9-migration-evaluation.md) steps
(2)–(5) were therefore exercised by the maintainer on a real libvirtd lab host,
and the migration was accepted on that basis. These were **not** reproduced in
this PR's CI (which has no libvirtd) — they are owner-attested. Scope covered:

1. **State migration.** 0.8.x → 0.9.x is a state-shape change *and* a
   block→attribute reshape, so a real `tofu plan` against existing state shows
   destroy/create, not in-place update. Lab is reproducible (destroy + re-apply
   acceptable); `production` defines **no resources**, so it has no state to
   migrate.
2. **Domain XML acceptance.** libvirt accepts the re-shaped domain — the
   guest-agent channel (`source = { unix = {} }`), the serial console
   (`serials`/`consoles`), and `os = { type = "hvm" }` with no explicit machine
   type.
3. **cloud-init via CD-ROM.** The ISO-as-volume-as-`cdrom` path is detected by
   cloud-init (NoCloud `cidata`); the ADR-0004 baseline applies.
4. **IP read-out timing.** `data.libvirt_domain_interface_addresses` populates
   `ip_address` once the guest leases (it may be `null` on first apply and
   converge on refresh — the 0.8.x `wait_for_lease` no longer blocks).
5. **Talos static IPs / apply ordering.** The native `ips[].dhcp.hosts`
   reservations pin each MAC→IP and the cluster reaches a healthy state
   (config-apply → bootstrap → `kubeconfig`) with the configuration **as
   merged** — no explicit interface wait was needed; the talos provider's own
   connect-retry on `talos_machine_configuration_apply` covers the brief
   first-boot lease window. (0.9.8 exposes no interface-level `wait_for_lease`/
   `wait_for_ip`; if a future host shows a race, gate the apply behind a
   `time_sleep` or a retried interface-addresses read.)
6. **Maintenance-horizon check** (ADR-0009 step 5): no outstanding 0.8.x
   security advisory forcing us to stay.

## Consequences

**Positive**

- Moves off the bugfix-only 0.8.x line onto the actively developed 0.9.x.
- The Talos module loses the XSLT-on-XML hack for static leases — native,
  reviewable `dhcp.hosts`.
- The migration is now a single reviewable artifact (this ADR + its PR) with
  schema-correctness mechanically proven, instead of a desk inventory.

**Negative**

- A genuinely breaking, state-shape change: applying it against any environment
  with **live** 0.8.x state shows destroy/recreate, not in-place update (lab is
  reproducible; production has no resources yet). `tofu plan` before `apply` on
  any future stateful environment.
- 0.9.x is more verbose (it mirrors the libvirt XML tree), so the modules carry
  more nesting than the 0.8.x blocks did.

## References

- [ADR-0002 — Pin `dmacvicar/libvirt` to `~> 0.8.0`](0002-pin-libvirt-provider-to-0.8.md)
- [ADR-0009 — Begin libvirt 0.9.x migration evaluation](0009-begin-libvirt-0.9-migration-evaluation.md)
- [ADR-0012 — libvirt 0.9.x schema-diff inventory](0012-libvirt-0.9-schema-diff-inventory.md)
- [ADR-0014 — Pin `siderolabs/talos` to `~> 0.11.0`](0014-pin-siderolabs-talos-provider.md)
- [`dmacvicar/terraform-provider-libvirt` v0.9.8 docs/examples](https://github.com/dmacvicar/terraform-provider-libvirt/tree/v0.9.8/docs)
- [v0.9.0 migration discussion](https://github.com/dmacvicar/terraform-provider-libvirt/discussions/1194)
