/**
 * RKE2 cluster Terraform module.
 *
 * Provisions a Rancher RKE2 cluster on Linux VMs by driving the official
 * RKE2 install script over SSH. Provider-agnostic at the cluster layer:
 * bring your own VMs from vSphere, OpenStack, Proxmox or bare metal.
 *
 * Flow:
 *   1. Install RKE2 server on the first control-plane node (cluster-init).
 *   2. Read the cluster join token over SSH with host-key verification.
 *   3. Install RKE2 server on the remaining control-plane nodes (joins).
 *   4. Install RKE2 agent on each worker node.
 *   5. Pull the kubeconfig and run the platform add-ons.
 */

terraform {
  required_version = ">= 1.6"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

# ---- Inputs ----------------------------------------------------------------

variable "cluster_name" {
  description = "Name of the RKE2 cluster (used as a tag, also written to /etc/rancher/rke2/config.yaml)."
  type        = string
}

variable "control_plane_nodes" {
  description = "Control plane node addresses. The first entry is the cluster-init node."
  type        = list(string)
  validation {
    condition     = length(var.control_plane_nodes) >= 1
    error_message = "Provide at least one control plane node (three recommended for HA)."
  }
}

variable "worker_nodes" {
  description = "Worker node addresses."
  type        = list(string)
  default     = []
}

variable "ssh_user" {
  description = "SSH user for node access. Must have passwordless sudo."
  type        = string
  default     = "rancher"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for node access."
  type        = string
}

variable "known_hosts_path" {
  description = "Path to an SSH known_hosts file containing every node's host key. Required so token capture and kubeconfig pull cannot be silently MITM'd."
  type        = string
}

variable "kubernetes_version" {
  description = "RKE2 version channel."
  type        = string
  default     = "v1.30.3+rke2r1"
}

variable "metallb_address_pool" {
  description = "CIDR or hyphen-delimited IP range MetalLB advertises for Services of type LoadBalancer (e.g. 10.10.20.200-10.10.20.220). Required on bare metal so ingress-nginx gets an external IP. Leave empty to skip MetalLB."
  type        = string
  default     = ""
}

variable "install_platform_addons" {
  description = "When true, install Argo CD, Ingress NGINX, cert-manager, kube-prometheus-stack, and Loki."
  type        = bool
  default     = true
}

# ---- Locals ----------------------------------------------------------------

locals {
  kubeconfig_path = "${path.module}/kubeconfig"
  ssh_opts        = "-o StrictHostKeyChecking=yes -o UserKnownHostsFile=${var.known_hosts_path}"

  # Hardened cluster config written to /etc/rancher/rke2/config.yaml on each
  # control-plane node. CIS profile, SELinux on, kubeconfig group-readable.
  server_config_yaml = <<-EOT
    cluster-name: ${var.cluster_name}
    cni: cilium
    disable-kube-proxy: true
    profile: cis-1.23
    selinux: true
    write-kubeconfig-mode: "0640"
  EOT

  init_node    = var.control_plane_nodes[0]
  join_servers = slice(var.control_plane_nodes, 1, length(var.control_plane_nodes))
}

# ---- Cluster-init node -----------------------------------------------------

resource "null_resource" "server_init" {
  triggers = {
    address = local.init_node
    version = var.kubernetes_version
  }

  connection {
    type        = "ssh"
    host        = local.init_node
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/rancher/rke2",
      "echo ${base64encode(local.server_config_yaml)} | base64 -d | sudo tee /etc/rancher/rke2/config.yaml >/dev/null",
      "curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION=${var.kubernetes_version} INSTALL_RKE2_TYPE=server sh -",
      "sudo systemctl enable --now rke2-server.service",
      # Wait for the API server to be ready before we hand out the token.
      "for i in $(seq 1 60); do sudo test -s /var/lib/rancher/rke2/server/node-token && break; sleep 5; done",
      "sudo cp /var/lib/rancher/rke2/server/node-token /tmp/node-token && sudo chmod 0644 /tmp/node-token",
    ]
  }
}

# ---- Capture the join token (host-key checked) -----------------------------

data "external" "node_token" {
  depends_on = [null_resource.server_init]
  program = [
    "bash", "-c",
    "ssh -i ${var.ssh_private_key_path} ${local.ssh_opts} ${var.ssh_user}@${local.init_node} 'sudo cat /tmp/node-token' | jq -Rn '{token: input}'",
  ]
}

# ---- Additional control plane nodes (HA) -----------------------------------

resource "null_resource" "server_join" {
  for_each = toset(local.join_servers)
  triggers = {
    address = each.key
    version = var.kubernetes_version
  }

  connection {
    type        = "ssh"
    host        = each.key
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/rancher/rke2",
      "echo ${base64encode(local.server_config_yaml)} | base64 -d | sudo tee /etc/rancher/rke2/config.yaml >/dev/null",
      "echo 'server: https://${local.init_node}:9345' | sudo tee -a /etc/rancher/rke2/config.yaml >/dev/null",
      "echo \"token: ${data.external.node_token.result.token}\" | sudo tee -a /etc/rancher/rke2/config.yaml >/dev/null",
      "curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION=${var.kubernetes_version} INSTALL_RKE2_TYPE=server sh -",
      "sudo systemctl enable --now rke2-server.service",
    ]
  }

  depends_on = [data.external.node_token]
}

# ---- Worker nodes ----------------------------------------------------------

resource "null_resource" "agent" {
  for_each = toset(var.worker_nodes)
  triggers = {
    address = each.key
    version = var.kubernetes_version
  }

  connection {
    type        = "ssh"
    host        = each.key
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mkdir -p /etc/rancher/rke2",
      "echo 'server: https://${local.init_node}:9345' | sudo tee /etc/rancher/rke2/config.yaml >/dev/null",
      "echo \"token: ${data.external.node_token.result.token}\" | sudo tee -a /etc/rancher/rke2/config.yaml >/dev/null",
      "curl -sfL https://get.rke2.io | sudo INSTALL_RKE2_VERSION=${var.kubernetes_version} INSTALL_RKE2_TYPE=agent sh -",
      "sudo systemctl enable --now rke2-agent.service",
    ]
  }

  depends_on = [data.external.node_token]
}

# ---- Pull the kubeconfig locally for the providers below -------------------

resource "null_resource" "kubeconfig" {
  triggers = { address = local.init_node }

  depends_on = [
    null_resource.server_init,
    null_resource.server_join,
  ]

  provisioner "local-exec" {
    command = "ssh -i ${var.ssh_private_key_path} ${local.ssh_opts} ${var.ssh_user}@${local.init_node} 'sudo cat /etc/rancher/rke2/rke2.yaml' | sed 's|127.0.0.1|${local.init_node}|' > ${local.kubeconfig_path} && chmod 0600 ${local.kubeconfig_path}"
  }
}

# ---- Platform add-ons via Helm --------------------------------------------

provider "kubernetes" {
  config_path = local.kubeconfig_path
}

provider "helm" {
  kubernetes {
    config_path = local.kubeconfig_path
  }
}

# MetalLB is mandatory on bare metal: without it, Services of type
# LoadBalancer (including the ingress-nginx Service) stay <pending> forever.
resource "helm_release" "metallb" {
  count            = var.install_platform_addons && var.metallb_address_pool != "" ? 1 : 0
  name             = "metallb"
  namespace        = "metallb-system"
  create_namespace = true
  repository       = "https://metallb.github.io/metallb"
  chart            = "metallb"
  version          = "0.14.8"
  depends_on       = [null_resource.kubeconfig]
}

resource "kubernetes_manifest" "metallb_pool" {
  count      = var.install_platform_addons && var.metallb_address_pool != "" ? 1 : 0
  depends_on = [helm_release.metallb]
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "IPAddressPool"
    metadata = {
      name      = "default-pool"
      namespace = "metallb-system"
    }
    spec = {
      addresses = [var.metallb_address_pool]
    }
  }
}

resource "kubernetes_manifest" "metallb_l2" {
  count      = var.install_platform_addons && var.metallb_address_pool != "" ? 1 : 0
  depends_on = [kubernetes_manifest.metallb_pool]
  manifest = {
    apiVersion = "metallb.io/v1beta1"
    kind       = "L2Advertisement"
    metadata = {
      name      = "default-l2"
      namespace = "metallb-system"
    }
    spec = {
      ipAddressPools = ["default-pool"]
    }
  }
}

resource "helm_release" "argocd" {
  count            = var.install_platform_addons ? 1 : 0
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.6.0"
  depends_on       = [null_resource.kubeconfig]
}

resource "helm_release" "ingress_nginx" {
  count            = var.install_platform_addons ? 1 : 0
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.11.2"

  # Wait for MetalLB so the Service of type LoadBalancer gets an address.
  depends_on = [
    null_resource.kubeconfig,
    helm_release.metallb,
  ]
}

resource "helm_release" "cert_manager" {
  count            = var.install_platform_addons ? 1 : 0
  name             = "cert-manager"
  namespace        = "cert-manager"
  create_namespace = true
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.15.3"
  set {
    name  = "installCRDs"
    value = "true"
  }
  depends_on = [null_resource.kubeconfig]
}

resource "helm_release" "prometheus" {
  count            = var.install_platform_addons ? 1 : 0
  name             = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "62.6.0"
  depends_on       = [null_resource.kubeconfig]
}

resource "helm_release" "loki" {
  count            = var.install_platform_addons ? 1 : 0
  name             = "loki"
  namespace        = "monitoring"
  create_namespace = false
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  version          = "6.15.0"

  # Filesystem-backed single-binary defaults: authenticated, 1 replica. For
  # HA, point loki.storage at an S3-compatible object store and raise the
  # singleBinary.replicas value via a values file or override.
  values = [
    yamlencode({
      loki = {
        auth_enabled = true
        commonConfig = { replication_factor = 1 }
        storage = {
          type        = "filesystem"
          bucketNames = { chunks = "chunks", ruler = "ruler", admin = "admin" }
        }
        schemaConfig = {
          configs = [{
            from         = "2024-01-01"
            store        = "tsdb"
            object_store = "filesystem"
            schema       = "v13"
            index        = { prefix = "loki_index_", period = "24h" }
          }]
        }
      }
      deploymentMode = "SingleBinary"
      read           = { replicas = 0 }
      write          = { replicas = 0 }
      backend        = { replicas = 0 }
      chunksCache    = { enabled = false }
      resultsCache   = { enabled = false }
      test           = { enabled = false }
      lokiCanary     = { enabled = false }
      gateway        = { enabled = false }
      singleBinary   = { replicas = 1 }
    }),
  ]

  depends_on = [helm_release.prometheus]
}

# ---- Outputs ---------------------------------------------------------------

output "cluster_name" {
  value = var.cluster_name
}

output "control_plane_init_address" {
  value = local.init_node
}

output "kubeconfig_path" {
  value = local.kubeconfig_path
}
