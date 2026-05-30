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

run "install_disk_rejects_relative_path" {
  command = plan

  variables {
    install_disk = "vda"
  }

  expect_failures = [var.install_disk]
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
