locals {
  # GiB-to-bytes factor. libvirt_volume.size is expressed in bytes; the
  # per-node disk-size specs in this module are expressed in GiB. (Mirrors
  # modules/libvirt-vm.)
  bytes_per_gib = 1073741824

  # All nodes keyed by name, tagged with their machine_type, merged from the
  # control-plane and worker maps. for_each over libvirt domains/volumes and
  # over talos_machine_configuration_apply iterates this single map.
  all_nodes = merge(
    { for name, spec in var.control_plane_nodes : name => merge(spec, { machine_type = "controlplane" }) },
    { for name, spec in var.worker_nodes : name => merge(spec, { machine_type = "worker" }) },
  )

  # The control-plane node that is bootstrapped: the first by sorted name.
  # Bootstrap runs exactly once, against one control-plane node.
  control_plane_names = sort(keys(var.control_plane_nodes))
  bootstrap_node_name = local.control_plane_names[0]
  bootstrap_node_ip   = var.control_plane_nodes[local.bootstrap_node_name].ip

  # Endpoints (control-plane IPs) for the generated talosconfig so talosctl
  # can reach any control-plane node.
  control_plane_ips = [for name in local.control_plane_names : var.control_plane_nodes[name].ip]

  # Kubernetes minor version (e.g. "1.32") for the Pod Security Admission
  # *-version pins, derived from var.kubernetes_version ("1.32.3" -> "1.32").
  kubernetes_minor = join(".", slice(split(".", var.kubernetes_version), 0, 2))

  # Hardening patches rendered from machineconfig/ templates. common applies
  # to every node; controlplane adds the API-server (PSA/audit/RBAC) knobs.
  common_patch = templatefile("${path.module}/machineconfig/common.yaml.tftpl", {
    install_disk     = var.install_disk
    time_servers     = var.time_servers
    registry_mirrors = var.registry_mirrors
  })

  control_plane_patch = templatefile("${path.module}/machineconfig/controlplane.yaml.tftpl", {
    pod_security_enforce_profile   = var.pod_security_enforce_profile
    pod_security_exempt_namespaces = var.pod_security_exempt_namespaces
    kubernetes_minor               = local.kubernetes_minor
  })

  # Ordered config-patch lists threaded into the machine_configuration data
  # sources. Order matters: later patches override earlier ones, so caller
  # extras come last.
  control_plane_config_patches = concat(
    [local.common_patch, local.control_plane_patch],
    var.extra_control_plane_config_patches,
  )

  worker_config_patches = concat(
    [local.common_patch],
    var.extra_worker_config_patches,
  )
}

# ---------------------------------------------------------------------------
# libvirt: network with static DHCP reservations, base image, per-node disks
# and domains. Talos boots directly from its disk image; no cloud-init.
# ---------------------------------------------------------------------------

# Dedicated NAT network with a static MAC->IP reservation per node, so every
# Talos API endpoint is known before any configuration is applied. (0.8.x
# binds reservations via ips.dhcp.hosts; the domain side sets addresses+mac.)
resource "libvirt_network" "talos" {
  name      = "${var.cluster_name}-net"
  mode      = "nat"
  domain    = "${var.cluster_name}.local"
  addresses = [var.network_cidr]
  autostart = true

  dhcp {
    enabled = true
  }

  dns {
    enabled = true

    dynamic "hosts" {
      for_each = local.all_nodes
      content {
        hostname = hosts.key
        ip       = hosts.value.ip
      }
    }
  }
}

# Single shared Talos base image, cloned per node as a backing store.
resource "libvirt_volume" "talos_base" {
  name   = "${var.cluster_name}-talos-base.qcow2"
  pool   = var.storage_pool
  source = var.talos_image
  format = "qcow2"
}

# Per-node root disk: a thin overlay on the shared Talos base image.
resource "libvirt_volume" "root" {
  for_each = local.all_nodes

  name           = "${var.cluster_name}-${each.key}-root.qcow2"
  pool           = var.storage_pool
  base_volume_id = libvirt_volume.talos_base.id
  size           = each.value.disk_gib * local.bytes_per_gib
  format         = "qcow2"
}

# Per-node domain. Boots from the Talos disk image directly: Talos is
# immutable and API-configured, so there is intentionally NO cloudinit disk
# and NO cloud-init user-data (contrast modules/libvirt-vm). The node comes up
# in Talos maintenance mode; the talos provider applies config over the API.
resource "libvirt_domain" "node" {
  for_each = local.all_nodes

  name       = "${var.cluster_name}-${each.key}"
  vcpu       = each.value.vcpus
  memory     = each.value.memory_mib
  autostart  = true
  qemu_agent = false

  disk {
    volume_id = libvirt_volume.root[each.key].id
  }

  network_interface {
    network_id     = libvirt_network.talos.id
    hostname       = each.key
    addresses      = [each.value.ip]
    mac            = each.value.mac
    wait_for_lease = true
  }

  console {
    type        = "pty"
    target_type = "serial"
    target_port = "0"
  }

  # No graphics device (ADR-0008 posture); serial console only.
}

# ---------------------------------------------------------------------------
# talos: secrets, machine configuration (with hardening patches), apply,
# bootstrap, and exported kubeconfig/talosconfig.
# ---------------------------------------------------------------------------

# Cluster CA, certs, and bootstrap token. Lives in state -> the environment
# that uses this module must use an encrypted remote backend (ADR-0011/0015).
resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

# Control-plane machine configuration, hardened via config_patches.
data "talos_machine_configuration" "controlplane" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "controlplane"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches     = local.control_plane_config_patches
}

# Worker machine configuration, hardened via the common config_patches.
data "talos_machine_configuration" "worker" {
  cluster_name       = var.cluster_name
  cluster_endpoint   = var.cluster_endpoint
  machine_type       = "worker"
  machine_secrets    = talos_machine_secrets.this.machine_secrets
  talos_version      = var.talos_version
  kubernetes_version = var.kubernetes_version
  config_patches     = local.worker_config_patches
}

# talosctl client configuration (talosconfig) targeting all control planes.
data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = local.control_plane_ips
  nodes                = [for name, node in local.all_nodes : node.ip]
}

# Apply the (type-appropriate) machine configuration to every node over the
# Talos API. On first apply the node is in maintenance mode (applied
# insecurely by the provider); thereafter it is an authenticated apply.
resource "talos_machine_configuration_apply" "node" {
  for_each = local.all_nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = each.value.machine_type == "controlplane" ? data.talos_machine_configuration.controlplane.machine_configuration : data.talos_machine_configuration.worker.machine_configuration
  node                        = each.value.ip
  endpoint                    = each.value.ip
  apply_mode                  = var.apply_mode

  depends_on = [libvirt_domain.node]
}

# Bootstrap etcd on the first control-plane node, exactly once.
resource "talos_machine_bootstrap" "this" {
  node                 = local.bootstrap_node_ip
  endpoint             = local.bootstrap_node_ip
  client_configuration = talos_machine_secrets.this.client_configuration

  depends_on = [talos_machine_configuration_apply.node]
}

# Retrieve the cluster kubeconfig once bootstrap has completed. This is the
# resource form (talos provider >= 0.7); the data source of the same name is
# deprecated and slated for removal in a later minor.
resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.bootstrap_node_ip
  endpoint             = local.bootstrap_node_ip

  depends_on = [talos_machine_bootstrap.this]
}
