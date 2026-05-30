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

  # --- Cross-variable invariants, asserted at plan time via
  # terraform_data.node_invariants preconditions (a single var validation
  # cannot reference another variable). ---

  # (a) Control-plane and worker node NAMES must be disjoint. merge() would
  # otherwise let a same-named worker silently drop a control-plane entry while
  # bootstrap_node_* still points at it -> a broken cluster.
  overlapping_node_names = setintersection(
    toset(keys(var.control_plane_nodes)),
    toset(keys(var.worker_nodes)),
  )

  # (b) Every node IP must be UNIQUE across both maps. A duplicate static lease
  # means two domains race for one address and wait_for_lease times out.
  all_node_ips    = [for name, node in local.all_nodes : node.ip]
  unique_node_ips = distinct(local.all_node_ips)

  # (c) Every node IP must be CONTAINED in network_cidr. There is no built-in
  # "ip in cidr", so compare each IP's host-network (the IP under the CIDR's
  # own prefix length) against the CIDR network address: equal => same subnet.
  network_prefix       = split("/", var.network_cidr)[1]
  network_address      = cidrhost(var.network_cidr, 0)
  node_ips_out_of_cidr = [for ip in local.all_node_ips : ip if cidrhost("${ip}/${local.network_prefix}", 0) != local.network_address]

  # (d) Every node MAC must be UNIQUE across both maps (compared case-folded:
  # 52:54:00:AB == 52:54:00:ab). The static-address flow keys DHCP leases by
  # MAC, so two domains with the same NIC MAC collide -- one steals the other's
  # lease and wait_for_lease hangs even when the IPs are unique.
  all_node_macs    = [for name, node in local.all_nodes : lower(node.mac)]
  unique_node_macs = distinct(local.all_node_macs)

  # (e) No node IP may be a network-reserved address of network_cidr: the
  # network address (cidrhost 0), the libvirt/dnsmasq gateway -- the first host,
  # cidrhost 1 -- or the broadcast (cidrhost -1, the last address). libvirt
  # cannot hand any of these to a VM, so wait_for_lease hangs / the endpoint
  # never comes up. Canonicalise each node IP (cidrhost "${ip}/32", 0) before
  # the set membership test so e.g. 10.5.0.01 still matches the gateway 10.5.0.1.
  network_reserved_ips = [
    cidrhost(var.network_cidr, 0),
    cidrhost(var.network_cidr, 1),
    cidrhost(var.network_cidr, -1),
  ]
  node_ips_reserved = [for ip in local.all_node_ips : ip if contains(local.network_reserved_ips, cidrhost("${ip}/32", 0))]

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

  # XSLT that injects a libvirt-native <dhcp><host> reservation per node into
  # the network XML (the provider has no native HCL block for this on 0.8.x).
  # Kept as a local (not inlined in the resource) per the HCL style guide.
  network_dhcp_hosts_xslt = templatefile("${path.module}/network-dhcp-hosts.xslt.tftpl", {
    nodes = local.all_nodes
  })
}

# ---------------------------------------------------------------------------
# Plan-time guard for cross-variable invariants that a single var validation
# cannot express (they reference more than one variable). terraform_data has
# no provider/infrastructure side effect; its preconditions fail the plan with
# a clear message before any libvirt/talos resource is created, and they are
# exercised by the mocked-provider tofu test suite.
# ---------------------------------------------------------------------------
resource "terraform_data" "node_invariants" {
  input = local.all_nodes

  lifecycle {
    precondition {
      condition     = length(local.overlapping_node_names) == 0
      error_message = "control_plane_nodes and worker_nodes must have disjoint names; overlapping name(s) would let a worker override a control-plane node: ${join(", ", local.overlapping_node_names)}."
    }

    precondition {
      condition     = length(local.unique_node_ips) == length(local.all_node_ips)
      error_message = "every node IP must be unique across control_plane_nodes and worker_nodes; duplicate static leases break wait_for_lease."
    }

    precondition {
      condition     = length(local.node_ips_out_of_cidr) == 0
      error_message = "every node IP must fall within network_cidr (${var.network_cidr}); out-of-subnet IP(s): ${join(", ", local.node_ips_out_of_cidr)}."
    }

    precondition {
      condition     = length(local.unique_node_macs) == length(local.all_node_macs)
      error_message = "every node MAC must be unique across control_plane_nodes and worker_nodes; duplicate NIC MACs collide on the MAC-keyed DHCP lease."
    }

    precondition {
      condition     = length(local.node_ips_reserved) == 0
      error_message = "node IP(s) must be usable host addresses, not the network address, gateway (first host), or broadcast of network_cidr (${var.network_cidr}): ${join(", ", local.node_ips_reserved)}."
    }
  }
}

# ---------------------------------------------------------------------------
# libvirt: network with static DHCP reservations, base image, per-node disks
# and domains. Talos boots directly from its disk image; no cloud-init.
# ---------------------------------------------------------------------------

# Dedicated NAT network with a static MAC->IP DHCP reservation per node, so
# every Talos API endpoint is known and stable before any configuration is
# applied. dmacvicar/libvirt 0.8.x has no native HCL block for DHCP host
# reservations (the dhcp{} block only carries `enabled`), so the reservations
# are injected as libvirt-native <dhcp><host> elements via an XSLT transform on
# the network XML (xml.xslt below). The dns{} hosts add matching DNS A records
# (name resolution); they do NOT, on their own, pin the lease.
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

  # Inject one libvirt-native <host mac= name= ip=/> DHCP reservation per node
  # into the auto-generated <dhcp> element (see network-dhcp-hosts.xslt.tftpl).
  # This is what guarantees each node receives its declared IP, which the talos
  # provider then targets. 0.8.x exposes no native reservation block, so XSLT.
  xml {
    xslt = local.network_dhcp_hosts_xslt
  }
}

# Single shared Talos base image, cloned per node as a backing store. The
# format follows var.talos_image_format so a raw factory image is not misread
# as qcow2 (the per-node overlays below are always qcow2 overlays on top).
resource "libvirt_volume" "talos_base" {
  name   = "${var.cluster_name}-talos-base.${var.talos_image_format == "qcow2" ? "qcow2" : "img"}"
  pool   = var.storage_pool
  source = var.talos_image
  format = var.talos_image_format
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

  # On destroy (a node removed from the maps, or `tofu destroy`), whether to
  # reset the node so it leaves etcd/Kubernetes cleanly instead of just
  # deleting the VM and leaving stale etcd membership / a stale Kubernetes
  # node.
  #
  # Default OFF (reset=false is a provider no-op). To enable clean scale-down
  # of a HEALTHY cluster, flip reset=true here (a one-line, reviewed change).
  # Caveat: with graceful=true an enabled reset performs an etcd leave, which
  # BLOCKS `tofu destroy` waiting on the node -- so to remove an already-dead
  # node, keep reset=false (or `tofu state rm` it) and clean etcd membership
  # out of band (see runbooks/talos/reset-node.sh, `talosctl etcd remove-member`).
  #
  # Why a literal and not a variable: the talos provider types on_destroy.reset
  # as a plain bool that cannot accept an UNKNOWN value, and `tofu validate`
  # (run in CI) evaluates input variables as unknown -- so wiring a `var` here
  # fails validate ("the target type cannot handle unknown values"). All three
  # fields are set explicitly because an unset (computed) field is also unknown.
  on_destroy = {
    reset    = false
    graceful = true
    reboot   = false
  }

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
