# Negative tests: every input validation in variables.tf must reject bad
# input at plan time, not surface it as a libvirt apply error.
#
# The libvirt provider is mocked (mock_provider) so these run with
# `command = plan` and need no libvirtd. Each run sets one bad value and
# asserts the matching variable's validation fails via expect_failures.

mock_provider "libvirt" {}

# Baseline valid inputs; each run overrides exactly the field under test.
variables {
  vm_name        = "valid-host-01"
  base_image     = "/var/lib/libvirt/images/noble.img"
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIValidKeyMaterialBase64xxxxxxxxxxxxxxxxxxxx tester@host"
}

run "vm_name_rejects_uppercase" {
  command = plan

  variables {
    vm_name = "Invalid-Host"
  }

  expect_failures = [var.vm_name]
}

run "vm_name_rejects_leading_hyphen" {
  command = plan

  variables {
    vm_name = "-leading-hyphen"
  }

  expect_failures = [var.vm_name]
}

run "vm_name_rejects_trailing_hyphen" {
  command = plan

  variables {
    vm_name = "trailing-hyphen-"
  }

  expect_failures = [var.vm_name]
}

run "vm_name_rejects_over_63_chars" {
  command = plan

  variables {
    # 65 characters: past the 63-character RFC 1123 label limit.
    vm_name = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  }

  expect_failures = [var.vm_name]
}

run "ssh_public_key_rejects_empty" {
  command = plan

  variables {
    ssh_public_key = ""
  }

  expect_failures = [var.ssh_public_key]
}

run "ssh_public_key_rejects_garbage" {
  command = plan

  variables {
    ssh_public_key = "not-a-real-ssh-key"
  }

  expect_failures = [var.ssh_public_key]
}

run "memory_mib_rejects_below_floor" {
  command = plan

  variables {
    # Documented floor is 512 MiB; 256 must be rejected.
    memory_mib = 256
  }

  expect_failures = [var.memory_mib]
}

run "additional_disks_rejects_duplicate_names" {
  command = plan

  variables {
    additional_disks = [
      { name = "data", size_gib = 10 },
      { name = "data", size_gib = 20 },
    ]
  }

  expect_failures = [var.additional_disks]
}

run "additional_disks_rejects_more_than_25" {
  command = plan

  variables {
    # 26 disks: past the vdb-vdz device-letter range, which would otherwise
    # derive an invalid device name (vd) instead of failing at plan.
    additional_disks = [for i in range(26) : { name = "disk-${i}", size_gib = 1 }]
  }

  expect_failures = [var.additional_disks]
}
