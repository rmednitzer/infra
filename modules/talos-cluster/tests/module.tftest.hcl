# Positive tests for modules/talos-cluster. BOTH providers are mocked
# (mock_provider "libvirt" and "talos"), so the suite needs no libvirtd, no
# talosctl, and no real cluster -- it runs with `command = plan`. It asserts
# the config-generation locals, the control-plane/worker resource counts, and
# that the rendered hardening patches carry the PSA / audit / sysctl /
# kubelet invariants the module promises (C2, C6).

mock_provider "libvirt" {}
mock_provider "talos" {}

variables {
  cluster_name     = "lab-talos"
  cluster_endpoint = "https://10.5.0.10:6443"
  talos_image      = "/var/lib/libvirt/images/talos-v1.10.5-nocloud-amd64.qcow2"

  control_plane_nodes = {
    cp-01 = { ip = "10.5.0.10", mac = "52:54:00:00:00:10" }
  }
  worker_nodes = {
    work-01 = { ip = "10.5.0.20", mac = "52:54:00:00:00:20" }
    work-02 = { ip = "10.5.0.21", mac = "52:54:00:00:00:21" }
  }
}

run "node_counts_and_resource_fanout" {
  command = plan

  # 1 control-plane + 2 workers = 3 nodes -> 3 root volumes, 3 domains,
  # 3 machine-configuration-apply resources, plus exactly one shared base
  # volume, one network, one secrets resource, and one bootstrap.
  assert {
    condition     = length(local.all_nodes) == 3
    error_message = "1 control-plane + 2 workers must merge into 3 nodes."
  }

  assert {
    condition     = length(libvirt_domain.node) == 3
    error_message = "3 nodes must produce 3 libvirt domains."
  }

  assert {
    condition     = length(libvirt_volume.root) == 3
    error_message = "3 nodes must produce 3 per-node root volumes."
  }

  assert {
    condition     = length(talos_machine_configuration_apply.node) == 3
    error_message = "3 nodes must produce 3 machine-configuration-apply resources."
  }
}

run "network_dhcp_reservation_per_node" {
  command = plan

  # 0.9.x exposes native DHCP host reservations (ips[].dhcp.hosts); the module
  # declares one MAC->IP reservation per node, which is what pins each lease so
  # every VM gets its declared static IP. (Replaces the 0.8.x XSLT transform on
  # the network XML; the dns{} hosts only add DNS records, not leases.)
  assert {
    condition = length([
      for h in libvirt_network.talos.ips[0].dhcp.hosts :
      h if h.mac == "52:54:00:00:00:10" && h.ip == "10.5.0.10" && h.name == "cp-01"
    ]) == 1
    error_message = "the network must carry a DHCP reservation pinning the control-plane node's MAC to its IP."
  }

  assert {
    condition = length([
      for h in libvirt_network.talos.ips[0].dhcp.hosts :
      h if h.mac == "52:54:00:00:00:20" && h.ip == "10.5.0.20" && h.name == "work-01"
    ]) == 1
    error_message = "the network must carry a DHCP reservation for each worker node."
  }

  # One reservation per node (1 control-plane + 2 workers).
  assert {
    condition     = length(libvirt_network.talos.ips[0].dhcp.hosts) == 3
    error_message = "the network must carry one DHCP reservation per node."
  }
}

run "on_destroy_reset_defaults_off" {
  command = plan

  # Default: reset=false (provider no-op on destroy) so `tofu destroy` never
  # blocks waiting on an unreachable node to gracefully leave etcd. Enabling
  # clean scale-down is a documented one-line flip (see main.tf on_destroy).
  assert {
    condition     = talos_machine_configuration_apply.node["cp-01"].on_destroy.reset == false
    error_message = "on_destroy reset must be off by default (no reset on destroy)."
  }
}

run "secret_arguments_are_write_only" {
  command = plan

  # ADR-0017: the per-node config apply and the bootstrap pass the client TLS
  # credentials and the rendered machine config through the write-only (_wo)
  # arguments, so neither is persisted in those resources' state. Asserting
  # the _wo attributes themselves proves nothing (write-only values always
  # plan/read as null no matter what was assigned); the decidable invariant
  # is that their state-persisted twin arguments stay UNSET -- the provider
  # enforces exactly-one-of per pair, so unset twins pin the _wo path.
  assert {
    condition     = talos_machine_configuration_apply.node["cp-01"].machine_configuration_input == null
    error_message = "machine config must flow through machine_configuration_input_wo; the persisted machine_configuration_input must stay unset."
  }

  assert {
    condition     = talos_machine_configuration_apply.node["cp-01"].client_configuration == null
    error_message = "client credentials must flow through client_configuration_wo; the persisted client_configuration must stay unset."
  }

  assert {
    condition     = talos_machine_bootstrap.this.client_configuration == null
    error_message = "bootstrap client credentials must flow through client_configuration_wo; the persisted client_configuration must stay unset."
  }
}

run "bootstrap_targets_first_control_plane" {
  command = plan

  # Bootstrap runs against the first control-plane node by sorted name.
  assert {
    condition     = local.bootstrap_node_name == "cp-01"
    error_message = "the bootstrap node must be the first control-plane node by sorted name."
  }

  assert {
    condition     = local.bootstrap_node_ip == "10.5.0.10"
    error_message = "the bootstrap node IP must be cp-01's IP."
  }

  assert {
    condition     = talos_machine_bootstrap.this.node == "10.5.0.10"
    error_message = "talos_machine_bootstrap must target the bootstrap node IP."
  }
}

run "kubernetes_minor_is_derived" {
  command = plan

  variables {
    kubernetes_version = "1.32.3"
  }

  # The PSA *-version pins derive from the K8s minor: "1.32.3" -> "1.32".
  assert {
    condition     = local.kubernetes_minor == "1.32"
    error_message = "kubernetes_minor must be the major.minor slice of kubernetes_version."
  }
}

run "control_plane_patch_carries_psa_restricted" {
  command = plan

  # C2 invariant: the control-plane patch enforces Pod Security Admission at
  # the configured profile (default restricted) and pins audit/warn at
  # restricted.
  assert {
    condition     = strcontains(local.control_plane_patch, "name: PodSecurity")
    error_message = "control-plane patch must configure the PodSecurity admission plugin."
  }

  assert {
    condition     = strcontains(local.control_plane_patch, "enforce: \"restricted\"")
    error_message = "control-plane patch must enforce the restricted Pod Security profile by default."
  }

  assert {
    condition     = strcontains(local.control_plane_patch, "kind: PodSecurityConfiguration")
    error_message = "control-plane patch must use a PodSecurityConfiguration admission config."
  }
}

run "control_plane_patch_carries_audit_logging" {
  command = plan

  # C2 invariant: explicit Kubernetes API audit policy.
  assert {
    condition     = strcontains(local.control_plane_patch, "auditPolicy:")
    error_message = "control-plane patch must set an API server audit policy."
  }

  assert {
    condition     = strcontains(local.control_plane_patch, "kind: Policy")
    error_message = "audit policy must be an audit.k8s.io Policy document."
  }

  assert {
    condition     = strcontains(local.control_plane_patch, "level: RequestResponse")
    error_message = "audit policy must log RequestResponse for sensitive resources."
  }

  assert {
    condition     = strcontains(local.control_plane_patch, "profiling: \"false\"")
    error_message = "control-plane patch must disable API server profiling (CIS-K8s 1.2)."
  }

  # Audit rules are first-match-wins: the sensitive-resource RequestResponse
  # rule MUST precede the broad read-noise None rule, or reads of
  # secrets/configmaps/RBAC are matched by None first and never audited. Find
  # each rule's index in the decoded policy and assert the ordering directly.
  assert {
    condition = (
      [for i, r in yamldecode(local.control_plane_patch).cluster.apiServer.auditPolicy.rules : i if r.level == "RequestResponse"][0]
      <
      [for i, r in yamldecode(local.control_plane_patch).cluster.apiServer.auditPolicy.rules : i if r.level == "None"][0]
    )
    error_message = "the RequestResponse rule for secrets/RBAC must come BEFORE the broad level:None read rule (first-match-wins)."
  }

  # The secrets rule must not itself be a None rule: the first rule that lists
  # "secrets" as a resource must be at level RequestResponse.
  assert {
    condition = (
      [for r in yamldecode(local.control_plane_patch).cluster.apiServer.auditPolicy.rules : r.level
      if try(contains(flatten([for rg in r.resources : rg.resources]), "secrets"), false)][0] == "RequestResponse"
    )
    error_message = "the audit rule matching secrets must be at level RequestResponse, not None."
  }
}

run "rendered_patches_are_valid_yaml" {
  command = plan

  # The hardening patches are templatefile-rendered YAML threaded into
  # config_patches. A malformed indent would only surface at apply against a
  # real cluster; assert here that both render to parseable YAML.
  assert {
    condition     = can(yamldecode(local.common_patch))
    error_message = "the common hardening patch must render to valid YAML."
  }

  assert {
    condition     = can(yamldecode(local.control_plane_patch))
    error_message = "the control-plane hardening patch must render to valid YAML."
  }

  # And that the decoded structure has the expected top-level shape Talos
  # expects (machine.* on common, cluster.apiServer.* on control-plane).
  assert {
    condition     = yamldecode(local.common_patch).machine.install.disk == "/dev/vda"
    error_message = "decoded common patch must set machine.install.disk."
  }

  assert {
    condition     = yamldecode(local.control_plane_patch).cluster.apiServer.admissionControl[0].name == "PodSecurity"
    error_message = "decoded control-plane patch must set the PodSecurity admission plugin."
  }
}

run "common_patch_carries_kspp_sysctls_and_kubelet_hardening" {
  command = plan

  # C2 invariant: KSPP sysctls and kubelet hardening on every node.
  assert {
    condition     = strcontains(local.common_patch, "kernel.kptr_restrict: \"2\"")
    error_message = "common patch must set the KSPP kernel.kptr_restrict sysctl."
  }

  assert {
    condition     = strcontains(local.common_patch, "kernel.unprivileged_bpf_disabled: \"1\"")
    error_message = "common patch must disable unprivileged BPF (KSPP)."
  }

  assert {
    condition     = strcontains(local.common_patch, "net.ipv4.conf.all.rp_filter: \"1\"")
    error_message = "common patch must enable reverse-path filtering (anti-spoofing)."
  }

  assert {
    condition     = strcontains(local.common_patch, "anonymous-auth: \"false\"")
    error_message = "common patch must disable kubelet anonymous auth (CIS-K8s 4.2)."
  }

  assert {
    condition     = strcontains(local.common_patch, "event-qps: \"5\"")
    error_message = "common patch must set a positive kubelet event-qps (CIS-K8s 4.2; 0 = unlimited)."
  }

  assert {
    condition     = strcontains(local.common_patch, "rbac: true")
    error_message = "common patch must assert Talos apid RBAC is enabled."
  }

  assert {
    condition     = strcontains(local.common_patch, "disk: /dev/vda")
    error_message = "common patch must set the Talos install disk."
  }
}

run "config_patch_ordering_puts_caller_extras_last" {
  command = plan

  variables {
    extra_control_plane_config_patches = ["# caller-cp-override"]
    extra_worker_config_patches        = ["# caller-worker-override"]
  }

  # Caller extras must come AFTER the module's hardening patches so they can
  # override the baseline (Talos applies patches in order).
  assert {
    condition     = local.control_plane_config_patches[length(local.control_plane_config_patches) - 1] == "# caller-cp-override"
    error_message = "caller control-plane extras must be appended last."
  }

  assert {
    condition     = length(local.control_plane_config_patches) == 3
    error_message = "control-plane patches must be [common, controlplane, caller-extra]."
  }

  assert {
    condition     = local.worker_config_patches[length(local.worker_config_patches) - 1] == "# caller-worker-override"
    error_message = "caller worker extras must be appended last."
  }
}

run "static_ip_wiring_on_domains_and_network" {
  command = plan

  # Each domain declares its MAC on the interface; the matching network DHCP
  # reservation (see network_dhcp_reservation_per_node) pins that MAC to the
  # node's static IP, so the Talos API endpoint is known before config apply.
  # 0.9.x has no interface-level addresses/hostname/wait_for_lease (0.8.x did);
  # the reservation is the single source of truth for the IP.
  assert {
    condition     = libvirt_domain.node["cp-01"].devices.interfaces[0].mac.address == "52:54:00:00:00:10"
    error_message = "cp-01 domain must declare its MAC on the network interface."
  }

  assert {
    condition = one([
      for h in libvirt_network.talos.ips[0].dhcp.hosts : h.ip if h.name == "cp-01"
    ]) == "10.5.0.10"
    error_message = "the network reservation for cp-01 must pin its static IP."
  }

  assert {
    condition     = length(libvirt_network.talos.dns.host) == 3
    error_message = "the network must carry a DNS host entry per node."
  }
}

run "control_plane_only_cluster_has_no_workers" {
  command = plan

  variables {
    worker_nodes = {}
  }

  assert {
    condition     = length(local.all_nodes) == 1
    error_message = "a control-plane-only cluster must have exactly the control-plane node(s)."
  }

  assert {
    condition     = length(talos_machine_configuration_apply.node) == 1
    error_message = "a control-plane-only cluster must apply config to one node."
  }
}

run "ha_three_control_plane_nodes" {
  command = plan

  variables {
    control_plane_nodes = {
      cp-01 = { ip = "10.5.0.10", mac = "52:54:00:00:00:10" }
      cp-02 = { ip = "10.5.0.11", mac = "52:54:00:00:00:11" }
      cp-03 = { ip = "10.5.0.12", mac = "52:54:00:00:00:12" }
    }
    worker_nodes = {}
  }

  assert {
    condition     = length(local.control_plane_ips) == 3
    error_message = "an HA cluster must expose three control-plane endpoints in the talosconfig."
  }

  assert {
    condition     = local.bootstrap_node_name == "cp-01"
    error_message = "even with three control planes, bootstrap targets exactly the first by name."
  }
}
