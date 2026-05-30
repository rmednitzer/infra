# Negative tests for modules/talos-cluster: every input validation in
# variables.tf must reject bad input at plan time. BOTH providers are mocked
# so these run with `command = plan` and need no libvirtd / talosctl.

mock_provider "libvirt" {}
mock_provider "talos" {}

# Baseline valid inputs; each run overrides exactly the field under test.
variables {
  cluster_name     = "lab-talos"
  cluster_endpoint = "https://10.5.0.10:6443"
  talos_image      = "/var/lib/libvirt/images/talos.qcow2"

  control_plane_nodes = {
    cp-01 = { ip = "10.5.0.10", mac = "52:54:00:00:00:10" }
  }
}

run "cluster_name_rejects_uppercase" {
  command = plan

  variables {
    cluster_name = "Lab-Talos"
  }

  expect_failures = [var.cluster_name]
}

run "cluster_endpoint_rejects_missing_scheme" {
  command = plan

  variables {
    cluster_endpoint = "10.5.0.10:6443"
  }

  expect_failures = [var.cluster_endpoint]
}

run "cluster_endpoint_rejects_missing_port" {
  command = plan

  variables {
    cluster_endpoint = "https://10.5.0.10"
  }

  expect_failures = [var.cluster_endpoint]
}

run "talos_image_rejects_empty" {
  command = plan

  variables {
    talos_image = ""
  }

  expect_failures = [var.talos_image]
}

run "talos_version_rejects_non_semver" {
  command = plan

  variables {
    talos_version = "1.10.5"
  }

  expect_failures = [var.talos_version]
}

run "kubernetes_version_rejects_leading_v" {
  command = plan

  variables {
    kubernetes_version = "v1.32.3"
  }

  expect_failures = [var.kubernetes_version]
}

run "control_plane_rejects_empty" {
  command = plan

  variables {
    control_plane_nodes = {}
  }

  expect_failures = [var.control_plane_nodes]
}

run "control_plane_rejects_even_count" {
  command = plan

  variables {
    control_plane_nodes = {
      cp-01 = { ip = "10.5.0.10", mac = "52:54:00:00:00:10" }
      cp-02 = { ip = "10.5.0.11", mac = "52:54:00:00:00:11" }
    }
  }

  expect_failures = [var.control_plane_nodes]
}

run "control_plane_rejects_bad_ip" {
  command = plan

  variables {
    control_plane_nodes = {
      cp-01 = { ip = "not-an-ip", mac = "52:54:00:00:00:10" }
    }
  }

  expect_failures = [var.control_plane_nodes]
}

run "control_plane_rejects_out_of_range_octets" {
  command = plan

  variables {
    # Dotted-quad SHAPE but octets > 255: the old regex accepted this; the
    # cidrnetmask-based validation must reject it.
    control_plane_nodes = {
      cp-01 = { ip = "999.999.999.999", mac = "52:54:00:00:00:10" }
    }
  }

  expect_failures = [var.control_plane_nodes]
}

run "control_plane_rejects_zero_vcpus" {
  command = plan

  variables {
    control_plane_nodes = {
      cp-01 = { ip = "10.5.0.10", mac = "52:54:00:00:00:10", vcpus = 0 }
    }
  }

  expect_failures = [var.control_plane_nodes]
}

run "control_plane_rejects_fractional_vcpus" {
  command = plan

  variables {
    control_plane_nodes = {
      cp-01 = { ip = "10.5.0.10", mac = "52:54:00:00:00:10", vcpus = 1.5 }
    }
  }

  expect_failures = [var.control_plane_nodes]
}

run "control_plane_rejects_sub_floor_memory" {
  command = plan

  variables {
    control_plane_nodes = {
      cp-01 = { ip = "10.5.0.10", mac = "52:54:00:00:00:10", memory_mib = 256 }
    }
  }

  expect_failures = [var.control_plane_nodes]
}

run "control_plane_rejects_sub_floor_disk" {
  command = plan

  variables {
    # Below the 10 GiB Talos system-disk minimum.
    control_plane_nodes = {
      cp-01 = { ip = "10.5.0.10", mac = "52:54:00:00:00:10", disk_gib = 5 }
    }
  }

  expect_failures = [var.control_plane_nodes]
}

run "control_plane_rejects_bad_mac" {
  command = plan

  variables {
    control_plane_nodes = {
      cp-01 = { ip = "10.5.0.10", mac = "ZZ:ZZ" }
    }
  }

  expect_failures = [var.control_plane_nodes]
}

run "worker_rejects_bad_ip" {
  command = plan

  variables {
    worker_nodes = {
      work-01 = { ip = "999.999.999.999.0", mac = "52:54:00:00:00:20" }
    }
  }

  expect_failures = [var.worker_nodes]
}

run "worker_rejects_out_of_range_octets" {
  command = plan

  variables {
    # Dotted-quad shape, octets > 255: must be rejected as invalid IPv4.
    worker_nodes = {
      work-01 = { ip = "256.1.1.1", mac = "52:54:00:00:00:20" }
    }
  }

  expect_failures = [var.worker_nodes]
}

run "worker_rejects_negative_memory" {
  command = plan

  variables {
    worker_nodes = {
      work-01 = { ip = "10.5.0.20", mac = "52:54:00:00:00:20", memory_mib = -1 }
    }
  }

  expect_failures = [var.worker_nodes]
}

run "worker_rejects_sub_floor_disk" {
  command = plan

  variables {
    worker_nodes = {
      work-01 = { ip = "10.5.0.20", mac = "52:54:00:00:00:20", disk_gib = 0 }
    }
  }

  expect_failures = [var.worker_nodes]
}

run "network_cidr_rejects_out_of_range_octet" {
  command = plan

  variables {
    # Dotted-quad/prefix shape but octet > 255: the old regex accepted this.
    network_cidr = "999.5.0.0/24"
  }

  expect_failures = [var.network_cidr]
}

run "network_cidr_rejects_bad_prefix" {
  command = plan

  variables {
    # Prefix length > 32: the old regex accepted /99.
    network_cidr = "10.5.0.0/99"
  }

  expect_failures = [var.network_cidr]
}

run "talos_image_format_rejects_unknown" {
  command = plan

  variables {
    talos_image_format = "vmdk"
  }

  expect_failures = [var.talos_image_format]
}

run "install_disk_rejects_relative_path" {
  command = plan

  variables {
    install_disk = "vda"
  }

  expect_failures = [var.install_disk]
}

# --- Cross-variable invariants (terraform_data.node_invariants preconditions).
# These reference more than one variable, so they live on a resource
# precondition rather than a single-variable validation; expect_failures
# targets that resource. ---

run "rejects_overlapping_cp_and_worker_names" {
  command = plan

  variables {
    # A worker shares the control-plane node's name; merge() would otherwise
    # silently drop the control-plane entry.
    control_plane_nodes = {
      cp-01 = { ip = "10.5.0.10", mac = "52:54:00:00:00:10" }
    }
    worker_nodes = {
      cp-01 = { ip = "10.5.0.20", mac = "52:54:00:00:00:20" }
    }
  }

  expect_failures = [terraform_data.node_invariants]
}

run "rejects_duplicate_node_ips" {
  command = plan

  variables {
    control_plane_nodes = {
      cp-01 = { ip = "10.5.0.10", mac = "52:54:00:00:00:10" }
    }
    worker_nodes = {
      # Same IP as cp-01: duplicate static lease.
      work-01 = { ip = "10.5.0.10", mac = "52:54:00:00:00:20" }
    }
  }

  expect_failures = [terraform_data.node_invariants]
}

run "rejects_node_ip_outside_network_cidr" {
  command = plan

  variables {
    network_cidr = "10.5.0.0/24"
    control_plane_nodes = {
      cp-01 = { ip = "10.5.0.10", mac = "52:54:00:00:00:10" }
    }
    worker_nodes = {
      # Valid IPv4 but outside 10.5.0.0/24.
      work-01 = { ip = "10.6.0.20", mac = "52:54:00:00:00:20" }
    }
  }

  expect_failures = [terraform_data.node_invariants]
}

run "pod_security_profile_rejects_unknown" {
  command = plan

  variables {
    pod_security_enforce_profile = "ultra"
  }

  expect_failures = [var.pod_security_enforce_profile]
}

run "apply_mode_rejects_unknown" {
  command = plan

  variables {
    apply_mode = "yolo"
  }

  expect_failures = [var.apply_mode]
}
