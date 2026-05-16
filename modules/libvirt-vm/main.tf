locals {
  disk_size_bytes = var.disk_size_gib * 1073741824

  cloud_init_config = templatefile("${path.module}/cloud_init.cfg", {
    hostname       = var.vm_name
    ssh_public_key = var.ssh_public_key
  })
}

resource "libvirt_volume" "base" {
  name   = "${var.vm_name}-base.qcow2"
  pool   = var.storage_pool
  source = var.base_image
  format = "qcow2"
}

resource "libvirt_volume" "root" {
  name           = "${var.vm_name}-root.qcow2"
  pool           = var.storage_pool
  base_volume_id = libvirt_volume.base.id
  size           = local.disk_size_bytes
  format         = "qcow2"
}

resource "libvirt_volume" "data" {
  for_each = { for disk in var.additional_disks : disk.name => disk }

  name   = "${var.vm_name}-${each.key}.qcow2"
  pool   = var.storage_pool
  size   = each.value.size_gib * 1073741824
  format = "qcow2"
}

resource "libvirt_cloudinit_disk" "init" {
  name      = "${var.vm_name}-cloudinit.iso"
  pool      = var.storage_pool
  user_data = local.cloud_init_config
}

resource "libvirt_domain" "vm" {
  name       = var.vm_name
  vcpu       = var.vcpus
  memory     = var.memory_mib
  autostart  = var.autostart
  qemu_agent = true

  cloudinit = libvirt_cloudinit_disk.init.id

  disk {
    volume_id = libvirt_volume.root.id
  }

  dynamic "disk" {
    for_each = libvirt_volume.data
    content {
      volume_id = disk.value.id
    }
  }

  network_interface {
    network_name   = var.network_name
    wait_for_lease = var.wait_for_lease
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }
}
