variable "cluster_name" {
  description = "Talos/Kubernetes cluster name. Used as the libvirt domain name prefix, the Talos cluster name, and in generated talosconfig/kubeconfig contexts."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$", var.cluster_name))
    error_message = "cluster_name must be a valid RFC 1123 label: lowercase alphanumerics and hyphens, 1-63 characters, no leading or trailing hyphen."
  }
}

variable "cluster_endpoint" {
  description = "Kubernetes API endpoint URL the nodes register against and the kubeconfig targets, e.g. https://<vip-or-cp-ip>:6443. For a single control-plane node this is that node's IP; for HA, a virtual IP or load-balanced address fronting the control plane."
  type        = string

  validation {
    condition     = can(regex("^https://[^/]+:[0-9]+$", var.cluster_endpoint))
    error_message = "cluster_endpoint must be an https:// URL with an explicit port, e.g. https://10.5.0.10:6443."
  }
}

variable "talos_image" {
  description = "Path or URL to the Talos Linux disk image (nocloud/metal qcow2 or raw) used as the boot disk for every node. Download from the Talos image factory (factory.talos.dev) for the desired version, schematic, and architecture. Talos is API-only and immutable; it ignores cloud-init and is configured exclusively via the machine configuration applied over the Talos API."
  type        = string

  validation {
    condition     = length(trimspace(var.talos_image)) > 0
    error_message = "talos_image must not be empty."
  }
}

variable "talos_version" {
  description = "Talos version contract used to generate machine secrets and configuration, e.g. v1.10.5. Should match the version of the talos_image. Pinning is recommended for reproducible config generation."
  type        = string
  default     = "v1.10.5"

  validation {
    condition     = can(regex("^v[0-9]+\\.[0-9]+\\.[0-9]+$", var.talos_version))
    error_message = "talos_version must be a Talos semver tag like v1.10.5."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version Talos installs, e.g. 1.32.3 (no leading v). Must be a version supported by the chosen talos_version."
  type        = string
  default     = "1.32.3"

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version))
    error_message = "kubernetes_version must be a Kubernetes semver like 1.32.3 (no leading v)."
  }
}

variable "control_plane_nodes" {
  description = "Map of control-plane node name to its static IP, MAC address, and VM specs. The number of entries is the control-plane count (use 1 for single-node, 3 for HA). Static IPs are reserved on the libvirt network so the Talos API endpoints are known before configuration is applied. The first node (sorted by name) is bootstrapped."
  type = map(object({
    ip         = string
    mac        = string
    vcpus      = optional(number, 2)
    memory_mib = optional(number, 4096)
    disk_gib   = optional(number, 20)
  }))

  validation {
    condition     = length(var.control_plane_nodes) >= 1
    error_message = "at least one control-plane node is required."
  }

  validation {
    condition     = length(var.control_plane_nodes) % 2 == 1
    error_message = "control-plane node count should be odd (1, 3, 5) so etcd can form a quorum; an even count risks split-brain."
  }

  validation {
    condition     = alltrue([for n in values(var.control_plane_nodes) : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", n.ip))])
    error_message = "every control_plane_nodes ip must be a dotted-quad IPv4 address."
  }

  validation {
    condition     = alltrue([for n in values(var.control_plane_nodes) : can(regex("^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$", n.mac))])
    error_message = "every control_plane_nodes mac must be a colon-separated 6-octet MAC address."
  }
}

variable "worker_nodes" {
  description = "Map of worker node name to its static IP, MAC address, and VM specs. May be empty for a control-plane-only cluster (workloads then schedule on control-plane nodes only if their taint is removed downstream). Static IPs are reserved on the libvirt network."
  type = map(object({
    ip         = string
    mac        = string
    vcpus      = optional(number, 2)
    memory_mib = optional(number, 2048)
    disk_gib   = optional(number, 20)
  }))
  default = {}

  validation {
    condition     = alltrue([for n in values(var.worker_nodes) : can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", n.ip))])
    error_message = "every worker_nodes ip must be a dotted-quad IPv4 address."
  }

  validation {
    condition     = alltrue([for n in values(var.worker_nodes) : can(regex("^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$", n.mac))])
    error_message = "every worker_nodes mac must be a colon-separated 6-octet MAC address."
  }
}

variable "network_cidr" {
  description = "IPv4 CIDR for the module-created NAT network the Talos nodes attach to. The control-plane and worker node IPs must fall within this range. The module owns this network (named <cluster_name>-net) so the static IP-to-MAC DHCP reservations are guaranteed; it does not attach to a pre-existing network."
  type        = string
  default     = "10.5.0.0/24"

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.network_cidr))
    error_message = "network_cidr must be an IPv4 CIDR like 10.5.0.0/24."
  }
}

variable "storage_pool" {
  description = "Libvirt storage pool in which to create the Talos base image volume and the per-node root volumes."
  type        = string
  default     = "default"

  validation {
    condition     = length(trimspace(var.storage_pool)) > 0
    error_message = "storage_pool must not be empty."
  }
}

variable "install_disk" {
  description = "Block device inside each Talos VM that Talos installs itself onto, e.g. /dev/vda. Must match the disk bus the libvirt domain presents (virtio -> /dev/vdX). Threaded into machine.install.disk in the generated machine configuration."
  type        = string
  default     = "/dev/vda"

  validation {
    condition     = can(regex("^/dev/[a-z0-9]+$", var.install_disk))
    error_message = "install_disk must be an absolute device path like /dev/vda or /dev/sda."
  }
}

variable "time_servers" {
  description = "NTP servers Talos uses for time synchronization (machine.time.servers). Accurate time is a prerequisite for TLS and etcd; an empty list falls back to the Talos default pool."
  type        = list(string)
  default     = ["time.cloudflare.com"]
}

variable "registry_mirrors" {
  description = "Optional map of upstream registry host to a list of mirror/pull-through endpoints (machine.registries.mirrors). Empty by default. Example: { \"docker.io\" = [\"https://registry.example.internal\"] } to keep image pulls inside the network."
  type        = map(list(string))
  default     = {}
}

variable "pod_security_enforce_profile" {
  description = "Pod Security Admission enforce profile applied cluster-wide via the API server admission config. Defaults to \"restricted\" (the hardened baseline this module targets, per the CIS Kubernetes mapping). Talos's own default is the looser \"baseline\"; this module tightens it."
  type        = string
  default     = "restricted"

  validation {
    condition     = contains(["privileged", "baseline", "restricted"], var.pod_security_enforce_profile)
    error_message = "pod_security_enforce_profile must be one of privileged, baseline, or restricted."
  }
}

variable "pod_security_exempt_namespaces" {
  description = "Namespaces exempt from Pod Security Admission enforcement. Defaults to the system namespaces that legitimately run privileged pods (kube-system for CNI/CSI, and the Talos-managed namespaces). Keep this list as small as possible."
  type        = list(string)
  default     = ["kube-system"]
}

variable "extra_control_plane_config_patches" {
  description = "Additional raw Talos config patches (YAML strings, e.g. via yamlencode or file()) merged into the control-plane machine configuration AFTER the module's hardening patches, so a caller can extend or override the baseline for a specific cluster."
  type        = list(string)
  default     = []
}

variable "extra_worker_config_patches" {
  description = "Additional raw Talos config patches (YAML strings) merged into the worker machine configuration after the module's hardening patches."
  type        = list(string)
  default     = []
}

variable "apply_mode" {
  description = "talos_machine_configuration_apply mode. \"auto\" lets Talos apply immediately (rebooting if the change requires it); \"staged\" writes the config to be applied on the next reboot; \"staged_if_needing_reboot\" applies in place when possible and stages only changes that need a reboot. Pre-bootstrap (maintenance mode) the provider applies insecurely regardless; this governs subsequent applies."
  type        = string
  default     = "auto"

  validation {
    condition     = contains(["auto", "staged", "staged_if_needing_reboot"], var.apply_mode)
    error_message = "apply_mode must be one of auto, staged, or staged_if_needing_reboot (the values the talos provider accepts)."
  }
}
