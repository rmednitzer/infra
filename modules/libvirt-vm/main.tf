locals {
  # GiB-to-bytes factor. libvirt_volume.capacity is expressed in bytes; every
  # disk-size variable in this module is expressed in GiB.
  bytes_per_gib = 1073741824

  disk_size_bytes = var.disk_size_gib * local.bytes_per_gib

  cloud_init_config = templatefile("${path.module}/cloud_init.cfg", {
    hostname       = var.vm_name
    ssh_public_key = var.ssh_public_key
  })

  cloud_init_meta_data = "instance-id: ${var.vm_name}\nlocal-hostname: ${var.vm_name}\n"

  # Ordered domain disk list for devices.disks. The libvirt 0.9.x domain
  # references disks as an ordered attribute list (not 0.8.x's auto-assigned
  # disk{} blocks), so the guest device node is assigned explicitly here: the
  # root overlay is vda, additional data disks take vdb, vdc, ... in declared
  # order, and the cloud-init ISO is attached last as a read-only SATA CD-ROM.
  # Every element carries the same attribute set so the list has one element
  # type (driver is null on the CD-ROM, whose ISO needs no qcow2 driver).
  root_disk = {
    device    = "disk"
    read_only = false
    source    = { volume = { pool = var.storage_pool, volume = libvirt_volume.root.name } }
    target    = { dev = "vda", bus = "virtio" }
    driver    = { type = "qcow2" }
  }

  data_disks = [
    for index, disk in var.additional_disks : {
      device    = "disk"
      read_only = false
      source    = { volume = { pool = var.storage_pool, volume = libvirt_volume.data[disk.name].name } }
      target    = { dev = "vd${substr("bcdefghijklmnopqrstuvwxyz", index, 1)}", bus = "virtio" }
      driver    = { type = "qcow2" }
    }
  ]

  cloudinit_disk = {
    device    = "cdrom"
    read_only = true
    source    = { volume = { pool = var.storage_pool, volume = libvirt_volume.cloudinit.name } }
    target    = { dev = "sda", bus = "sata" }
    driver    = null
  }

  domain_disks = concat([local.root_disk], local.data_disks, [local.cloudinit_disk])

  # libvirt 0.9.x graphics device, derived from var.graphics (null => no device,
  # preserving the ADR-0008 no-listener default). 0.9.x models graphics per
  # protocol (a vnc {} or spice {} attribute) rather than 0.8.x's flat
  # type/listen_type/listen_address block.
  graphics_devices = var.graphics == null ? [] : [{
    vnc = var.graphics.type == "vnc" ? {
      listen    = var.graphics.listen_address
      auto_port = var.graphics.autoport
    } : null
    spice = var.graphics.type == "spice" ? {
      listen    = var.graphics.listen_address
      auto_port = var.graphics.autoport
    } : null
  }]
}

resource "libvirt_volume" "base" {
  name = "${var.vm_name}-base.qcow2"
  pool = var.storage_pool

  target = {
    format = { type = "qcow2" }
  }

  # 0.9.x: the image source is uploaded via create.content.url (0.8.x: source).
  create = {
    content = { url = var.base_image }
  }
}

resource "libvirt_volume" "root" {
  name     = "${var.vm_name}-root.qcow2"
  pool     = var.storage_pool
  capacity = local.disk_size_bytes

  target = {
    format = { type = "qcow2" }
  }

  # 0.9.x: copy-on-write overlay via backing_store.path (0.8.x: base_volume_id).
  backing_store = {
    path   = libvirt_volume.base.path
    format = { type = "qcow2" }
  }
}

resource "libvirt_volume" "data" {
  for_each = { for disk in var.additional_disks : disk.name => disk }

  name     = "${var.vm_name}-${each.key}.qcow2"
  pool     = var.storage_pool
  capacity = each.value.size_gib * local.bytes_per_gib

  target = {
    format = { type = "qcow2" }
  }
}

# Generate the NoCloud cloud-init ISO on the host. In 0.9.x this resource only
# produces the ISO (exporting .path); it is no longer attached to the domain via
# a top-level `cloudinit = <id>` argument (0.8.x). meta_data + user_data carry
# the ADR-0004/0007 baseline unchanged.
resource "libvirt_cloudinit_disk" "init" {
  name      = "${var.vm_name}-cloudinit"
  user_data = local.cloud_init_config
  meta_data = local.cloud_init_meta_data
}

# Upload the generated cloud-init ISO into the storage pool so the domain can
# attach it as a CD-ROM (see local.cloudinit_disk). Format auto-detects to iso.
resource "libvirt_volume" "cloudinit" {
  name = "${var.vm_name}-cloudinit.iso"
  pool = var.storage_pool

  create = {
    content = { url = libvirt_cloudinit_disk.init.path }
  }
}

resource "libvirt_domain" "vm" {
  name        = var.vm_name
  type        = "kvm"
  vcpu        = var.vcpus
  memory      = var.memory_mib
  memory_unit = "MiB"
  autostart   = var.autostart
  running     = true

  os = {
    type = "hvm"
  }

  devices = {
    disks = local.domain_disks

    interfaces = [
      {
        type   = "network"
        model  = { type = "virtio" }
        source = { network = { network = var.network_name } }
      }
    ]

    # Serial console: a serial device plus a console aliased to it. Replaces
    # 0.8.x's single console{} block with target_type="serial"; serial-only
    # console, no graphics by default (ADR-0008).
    serials = [
      { target = { port = 0 } }
    ]

    consoles = [
      { target = { type = "serial", port = 0 } }
    ]

    # QEMU guest agent over a virtio channel (0.8.x convenience: qemu_agent =
    # true). The libvirt-managed unix socket carries the org.qemu.guest_agent.0
    # channel so the host can query the guest (e.g. interface addresses).
    channels = [
      {
        source = { unix = {} }
        target = { virt_io = { name = "org.qemu.guest_agent.0" } }
      }
    ]

    # No graphics device by default (var.graphics = null) so the secure
    # no-listener default from ADR-0008 holds. Operators who need SPICE/VNC for
    # a specific VM set var.graphics rather than forking the module.
    graphics = local.graphics_devices
  }
}

# Read the DHCP-leased address(es) for the domain. 0.9.x drops the 0.8.x
# wait_for_lease/network_interface[].addresses surface, so the IP is queried via
# this data source (source = "lease": the dnsmasq leases, no guest agent
# required). It depends on the domain via .id; the address only becomes known
# once the guest has booted and acquired a lease.
data "libvirt_domain_interface_addresses" "vm" {
  domain = libvirt_domain.vm.id
  source = "lease"
}
