/**
 * k3s edge cluster Terraform skeleton.
 *
 * Provisions a k3s cluster on lightweight Linux hosts. Designed for
 * trackside, factory floor or other edge environments where a full RKE2
 * control plane is too heavy.
 *
 * Installs the same platform add-on baseline as the RKE2 module so workloads
 * stay portable between datacentre and edge clusters.
 */

terraform {
  required_version = ">= 1.6"
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
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

variable "server_address" {
  description = "k3s server (control plane) host address."
  type        = string
}

variable "agent_addresses" {
  description = "List of k3s agent host addresses."
  type        = list(string)
  default     = []
}

variable "ssh_user" {
  description = "SSH user for node access."
  type        = string
  default     = "ubuntu"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key."
  type        = string
}

variable "known_hosts_path" {
  description = "Path to an SSH known_hosts file containing the server and agent host key fingerprints. Required so bootstrap SSH never silently trusts an unknown host."
  type        = string
}

variable "k3s_version" {
  description = "Pinned k3s version channel (e.g. v1.30.3+k3s1). Empty string uses the upstream stable channel."
  type        = string
  default     = "v1.30.3+k3s1"
}

variable "install_platform_addons" {
  description = "When true, install Argo CD, Ingress NGINX, cert-manager, kube-prometheus-stack, and Loki against the new k3s cluster."
  type        = bool
  default     = true
}

variable "metallb_address_pool" {
  description = "CIDR or hyphen-delimited IP range MetalLB advertises for Services of type LoadBalancer. Leave empty to skip MetalLB."
  type        = string
  default     = ""
}

# ---- Install k3s on the server --------------------------------------------

locals {
  k3s_install_env = var.k3s_version == "" ? "" : "INSTALL_K3S_VERSION=${var.k3s_version} "
  kubeconfig_path = "${path.module}/kubeconfig"
}

resource "null_resource" "k3s_server" {
  triggers = {
    address     = var.server_address
    k3s_version = var.k3s_version
  }

  connection {
    type        = "ssh"
    host        = var.server_address
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "remote-exec" {
    inline = [
      "curl -sfL https://get.k3s.io | ${local.k3s_install_env}sh -s - server --cluster-init --disable=traefik --write-kubeconfig-mode 0640",
    ]
  }
}

# ---- Install k3s agents ---------------------------------------------------

resource "null_resource" "k3s_agents" {
  for_each = toset(var.agent_addresses)
  triggers = {
    address     = each.key
    k3s_version = var.k3s_version
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      TOKEN="$(ssh -i ${var.ssh_private_key_path} -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${var.known_hosts_path} ${var.ssh_user}@${var.server_address} 'sudo cat /var/lib/rancher/k3s/server/node-token')"
      printf '%s\n' "$TOKEN" | ssh -i ${var.ssh_private_key_path} -o StrictHostKeyChecking=yes -o UserKnownHostsFile=${var.known_hosts_path} ${var.ssh_user}@${each.key} "read -r TOKEN; curl -sfL https://get.k3s.io | ${local.k3s_install_env}K3S_URL=https://${var.server_address}:6443 K3S_TOKEN=\$TOKEN sh -"
    EOT
  }

  depends_on = [null_resource.k3s_server]
}

# ---- Pull the kubeconfig locally for the providers below -------------------

resource "null_resource" "kubeconfig" {
  triggers = { address = var.server_address }

  depends_on = [null_resource.k3s_server]

  provisioner "local-exec" {
    command = join(" ", [
      "ssh",
      "-i ${var.ssh_private_key_path}",
      "-o StrictHostKeyChecking=yes",
      "-o UserKnownHostsFile=${var.known_hosts_path}",
      "${var.ssh_user}@${var.server_address}",
      "'sudo cat /etc/rancher/k3s/k3s.yaml'",
      "| sed 's/127.0.0.1/${var.server_address}/'",
      "> ${local.kubeconfig_path}",
      "&& chmod 0600 ${local.kubeconfig_path}",
    ])
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
  depends_on       = [null_resource.kubeconfig]
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

  # Edge clusters typically have constrained storage. Filesystem-backed
  # single-binary, single replica is the sane default. For HA at the edge,
  # point loki.storage at a central object store.
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

output "server_address" {
  value = var.server_address
}

output "agent_count" {
  value = length(var.agent_addresses)
}

output "kubeconfig_path" {
  value = local.kubeconfig_path
}
