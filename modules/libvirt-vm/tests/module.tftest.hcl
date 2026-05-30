# Positive tests: with valid inputs and a mocked libvirt provider, the
# module computes the values its contract promises -- the NoCloud meta-data
# string (ADR-0007), GiB->byte disk math, one volume per additional disk,
# and the ADR-0004 cloud-init security invariants.

mock_provider "libvirt" {}

variables {
  vm_name        = "app-server-01"
  base_image     = "/var/lib/libvirt/images/noble.img"
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIValidKeyMaterialBase64xxxxxxxxxxxxxxxxxxxx tester@host"
}

run "meta_data_is_deterministic_from_vm_name" {
  command = plan

  # ADR-0007: instance-id and local-hostname derive deterministically from
  # vm_name. local.cloud_init_meta_data feeds libvirt_cloudinit_disk.meta_data.
  assert {
    condition     = local.cloud_init_meta_data == "instance-id: app-server-01\nlocal-hostname: app-server-01\n"
    error_message = "cloud_init_meta_data must be 'instance-id: <vm_name>\\nlocal-hostname: <vm_name>\\n' (ADR-0007)."
  }

  assert {
    condition     = libvirt_cloudinit_disk.init.meta_data == "instance-id: app-server-01\nlocal-hostname: app-server-01\n"
    error_message = "libvirt_cloudinit_disk.init.meta_data must carry the deterministic NoCloud meta-data (ADR-0007)."
  }
}

run "root_disk_byte_math" {
  command = plan

  variables {
    disk_size_gib = 30
  }

  # 30 GiB expressed in bytes; libvirt_volume.size is bytes.
  assert {
    condition     = libvirt_volume.root.size == 30 * 1073741824
    error_message = "root volume size must equal disk_size_gib * 1073741824."
  }
}

run "additional_disk_byte_math_and_count" {
  command = plan

  variables {
    additional_disks = [
      { name = "data", size_gib = 10 },
      { name = "logs", size_gib = 5 },
    ]
  }

  # N additional_disks -> N data volumes.
  assert {
    condition     = length(libvirt_volume.data) == 2
    error_message = "two additional_disks must produce two data volumes."
  }

  assert {
    condition     = libvirt_volume.data["data"].size == 10 * 1073741824
    error_message = "data volume size must equal size_gib * 1073741824."
  }

  assert {
    condition     = libvirt_volume.data["logs"].size == 5 * 1073741824
    error_message = "logs volume size must equal size_gib * 1073741824."
  }
}

run "no_additional_disks_produces_no_data_volumes" {
  command = plan

  assert {
    condition     = length(libvirt_volume.data) == 0
    error_message = "with the default empty additional_disks, no data volumes must be created."
  }
}

run "cloud_init_enforces_adr0004_security_invariants" {
  command = plan

  # ADR-0004 invariant (the M4 security-enforcement gap): the rendered
  # cloud-init must lock the default user, disable root, and refuse SSH
  # password auth. Asserting on the rendered user_data proves the shipped
  # template still carries these directives.
  assert {
    condition     = strcontains(libvirt_cloudinit_disk.init.user_data, "ssh_pwauth: false")
    error_message = "cloud-init must set ssh_pwauth: false (ADR-0004)."
  }

  assert {
    condition     = strcontains(libvirt_cloudinit_disk.init.user_data, "disable_root: true")
    error_message = "cloud-init must set disable_root: true (ADR-0004)."
  }

  assert {
    condition     = strcontains(libvirt_cloudinit_disk.init.user_data, "lock_passwd: true")
    error_message = "cloud-init must set lock_passwd: true (ADR-0004)."
  }
}

run "graphics_omitted_by_default" {
  command = plan

  # ADR-0008: the default-shaped VM has no graphics listener.
  assert {
    condition     = length(libvirt_domain.vm.graphics) == 0
    error_message = "no graphics device must be present when var.graphics is null (ADR-0008)."
  }
}

run "ubuntu_2604_resolute_base_image_threads_through" {
  command = plan

  # Workstream A (Ubuntu 26.04 dual-support): base_image is a version-neutral
  # variable. A 26.04-style (resolute) value must flow into the base volume
  # source unchanged, and the distro-neutral cloud-init security invariants
  # (ADR-0004) must still render -- proving the module is not pinned to noble.
  variables {
    base_image = "/var/lib/libvirt/images/resolute-server-cloudimg-amd64.img"
  }

  assert {
    condition     = libvirt_volume.base.source == "/var/lib/libvirt/images/resolute-server-cloudimg-amd64.img"
    error_message = "a 26.04 (resolute) base_image must thread into libvirt_volume.base.source unchanged."
  }

  assert {
    condition     = strcontains(libvirt_cloudinit_disk.init.user_data, "ssh_pwauth: false")
    error_message = "the cloud-init security baseline (ADR-0004) must hold for a 26.04 base image too."
  }
}

run "graphics_override_threads_through" {
  command = plan

  variables {
    graphics = {
      type           = "vnc"
      listen_type    = "address"
      listen_address = "127.0.0.1"
    }
  }

  # ADR-0008 override knob: setting var.graphics adds exactly one device
  # with the requested type.
  assert {
    condition     = length(libvirt_domain.vm.graphics) == 1
    error_message = "setting var.graphics must add one graphics device."
  }

  assert {
    condition     = libvirt_domain.vm.graphics[0].type == "vnc"
    error_message = "graphics device type must match var.graphics.type."
  }
}
