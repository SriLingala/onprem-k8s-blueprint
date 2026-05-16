# On-prem to cloud mapping

This document explains how each platform concern is implemented on-prem
(RKE2 or k3s) versus on managed cloud Kubernetes (AKS, GKE, EKS). The
intent is that an engineer who learns one side can navigate the other.

## Cluster lifecycle

| On-prem (RKE2)                                | Cloud (AKS / GKE / EKS)                |
|-----------------------------------------------|----------------------------------------|
| `rke2_cluster` Terraform resource             | `azurerm_kubernetes_cluster` etc.      |
| Control plane runs on user-managed VMs        | Control plane managed by cloud         |
| Air-gapped install supported                  | Requires control plane reachability    |
| Rancher Manager UI for fleet view             | Cloud console for fleet view           |

## Identity for pods

| On-prem                                         | Cloud                                  |
|-------------------------------------------------|----------------------------------------|
| HashiCorp Vault Agent Injector                  | Workload Identity (AKS), GKE WI        |
| SPIFFE / SPIRE for cluster-internal identity    | Federated OIDC to cloud IAM            |
| Short-lived tokens issued by Vault              | Short-lived tokens issued by cloud IAM |

The conceptual model is identical: pods authenticate as themselves to get
short-lived credentials. The implementation differs.

## Storage

| On-prem                          | Cloud                              |
|----------------------------------|------------------------------------|
| Longhorn (replicated block)      | Azure Disk / GCE PD / EBS          |
| Ceph for larger estates          | Azure Files / Filestore / EFS      |
| Local-path for k3s edge          | Standard cloud volume claims       |

## Ingress

| On-prem                                | Cloud                                |
|----------------------------------------|--------------------------------------|
| MetalLB for L2/BGP load balancing      | Cloud load balancer auto-provisioned |
| NGINX Ingress Controller               | NGINX or cloud-native ingress        |
| External-DNS to on-prem DNS server     | External-DNS to Route53 / Cloud DNS  |

## Policy and admission

Same on both sides:

- OPA Gatekeeper for runtime policy
- Sentinel or OPA Conftest for Terraform-time policy
- Pod Security Standards as the baseline

## Observability

Identical on-prem and cloud. Both run:

- Prometheus + Grafana for metrics
- Loki for logs
- OpenTelemetry Collector for traces
- Alertmanager for alert routing

This is by design. Engineers should not have to learn a different
observability surface depending on which cluster their workload runs on.

## What is genuinely different

Two things you cannot fake parity on:

1. **Cluster bootstrap time.** Cloud cluster: 8 minutes. RKE2 on bare metal: 30-45 minutes plus hardware lead time. Plan capacity ahead.
2. **Scaling response.** Cloud autoscaler can spin up nodes in 90 seconds. On-prem, you either pre-provision capacity or you wait for someone to rack new hardware. Capacity planning matters more.

Everything else: same patterns, different glue.
