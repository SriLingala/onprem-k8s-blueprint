/**
 * RKE2 cluster Terraform skeleton.
 *
 * Provisions a Rancher RKE2 cluster on Linux VMs. Provider-agnostic at the
 * cluster layer: bring your own VMs from vSphere, OpenStack, Proxmox or
 * bare metal. This file focuses on the RKE2 lifecycle and platform install.
 */

terraform {
  required_version = ">= 1.6"
  required_providers {
    rke2 = {
      source  = "rancher/rke2"
      version = "~> 1.6"
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
  description = "Name of the RKE2 cluster."
  type        = string
}

variable "control_plane_nodes" {
  description = "List of control plane node addresses."
  type        = list(string)
}

variable "worker_nodes" {
  description = "List of worker node addresses."
  type        = list(string)
}

variable "ssh_user" {
  description = "SSH user for node access."
  type        = string
  default     = "rancher"
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for node access."
  type        = string
}

variable "kubernetes_version" {
  description = "RKE2 / Kubernetes version."
  type        = string
  default     = "v1.30.3+rke2r1"
}

# ---- Cluster ---------------------------------------------------------------

resource "rke2_cluster" "this" {
  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  dynamic "node" {
    for_each = var.control_plane_nodes
    content {
      address  = node.value
      role     = ["controlplane", "etcd"]
      ssh_user = var.ssh_user
      ssh_key  = file(var.ssh_private_key_path)
    }
  }

  dynamic "node" {
    for_each = var.worker_nodes
    content {
      address  = node.value
      role     = ["worker"]
      ssh_user = var.ssh_user
      ssh_key  = file(var.ssh_private_key_path)
    }
  }

  # Sensible defaults for regulated production.
  cluster_config = {
    cni                       = "cilium"
    disable_kube_proxy        = true
    profile                   = "cis"
    selinux                   = true
    write_kubeconfig_mode     = "0640"
  }
}

# ---- Platform add-ons via Helm --------------------------------------------

provider "kubernetes" {
  config_path = "${path.module}/kubeconfig"
}

provider "helm" {
  kubernetes {
    config_path = "${path.module}/kubeconfig"
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = "argocd"
  create_namespace = true
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "7.6.0"

  depends_on = [rke2_cluster.this]
}

resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  version          = "4.11.2"

  depends_on = [rke2_cluster.this]
}

resource "helm_release" "cert_manager" {
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
  depends_on = [rke2_cluster.this]
}

resource "helm_release" "prometheus" {
  name             = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  version          = "62.6.0"
  depends_on       = [rke2_cluster.this]
}

resource "helm_release" "loki" {
  name             = "loki"
  namespace        = "monitoring"
  create_namespace = false
  repository       = "https://grafana.github.io/helm-charts"
  chart            = "loki"
  version          = "6.15.0"
  depends_on       = [helm_release.prometheus]
}

# ---- Outputs ---------------------------------------------------------------

output "cluster_name" {
  value = rke2_cluster.this.name
}

output "kubeconfig_path" {
  value = "${path.module}/kubeconfig"
}
