# onprem-k8s-blueprint

A reference architecture and Terraform skeleton for running production
Kubernetes on-premises. Designed as the on-prem counterpart to my cloud
blueprints (`aks-platform`, `idp-banking-blueprint`) so the same platform
patterns work consistently across hybrid-cloud estates.

The blueprint targets two on-prem flavours:

| Flavour    | When to reach for it                                                          |
|------------|-------------------------------------------------------------------------------|
| **Rancher RKE2** | Enterprise on-prem with central fleet management. Air-gapped friendly.  |
| **k3s**          | Lightweight edge or factory-floor clusters. Single binary. ARM friendly.|

Both run the same platform add-ons (Argo CD, Prometheus, Grafana, Loki,
cert-manager, Ingress NGINX) so workloads move between on-prem and cloud
without rewrite.

## Why this exists

Most public Kubernetes blueprints assume a hyperscaler. Real organisations
run hybrid estates: cloud for elastic workloads, on-prem for regulated data,
edge for latency-sensitive operations. The platform team's job is to make
those feel like one platform to engineers.

This repo captures the on-prem half of that pattern, parallel to the cloud
work in [aks-platform](https://github.com/SriLingala/aks-platform).

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│ Central control plane (Rancher Manager or Argo CD ApplicationSet)│
└──────────────────────────────────────────────────────────────────┘
        │                          │                          │
        ▼                          ▼                          ▼
┌─────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│ Datacentre A    │      │ Datacentre B    │      │ Edge / Factory  │
│ RKE2 cluster    │      │ RKE2 cluster    │      │ k3s cluster     │
│  - 3 control    │      │  - 3 control    │      │  - 1 server     │
│  - N workers    │      │  - N workers    │      │  - N agents     │
└─────────────────┘      └─────────────────┘      └─────────────────┘
        │                          │                          │
        └──────── shared platform add-ons via GitOps ─────────┘
                  Argo CD. Prometheus. Loki. cert-manager.
                  Ingress NGINX. OPA Gatekeeper.
```

## Repository layout

```
onprem-k8s-blueprint/
├── .github/workflows/         terraform fmt/validate + helm lint on every PR
├── terraform/
│   ├── rke2/                  Terraform module for RKE2 on bare metal or VMs
│   └── k3s/                   Terraform module for k3s edge clusters
├── helm/
│   └── platform-addons/       Platform add-on chart (same as aks-platform)
├── docs/
│   ├── COMPARISON.md          How on-prem maps to AKS / GKE
│   ├── AIR-GAPPED.md          Notes for air-gapped operation
│   ├── EDGE.md                Notes for trackside / factory deployment
│   ├── REMOTE-STATE.md        How to wire a remote Terraform backend on-prem
│   └── BACKUP.md              etcd snapshots, Velero, restore drills
└── README.md
```

## Quick start (RKE2)

```bash
cd terraform/rke2
cp example.tfvars terraform.tfvars   # then edit
terraform init
terraform apply
```

This provisions a 3-control-plane plus 2-worker RKE2 cluster and installs
the platform add-on baseline (Argo CD, Ingress NGINX, cert-manager,
kube-prometheus-stack, Loki) plus MetalLB so Services of type LoadBalancer
get an actual IP. Configurable against any provider that exposes Linux VMs:
VMware vSphere, OpenStack, Proxmox, bare metal.

Once Argo CD is up it can take over reconciliation for everything else from
this repo's `helm/` directory.

## Quick start (k3s edge)

For lightweight edge or factory deployments where a full RKE2 control plane
is overkill:

```bash
cd terraform/k3s

# Capture the server's SSH host key so the token-capture step verifies it
# instead of trusting on first use.
ssh-keyscan <server-ip> > ./known_hosts.edge

cp edge.tfvars terraform.tfvars   # then edit
terraform init
terraform apply
```

Single k3s server plus N agents. Footprint is around 250 MB RAM for the
server. Runs comfortably on Raspberry Pi 5 or industrial NUCs. The same
platform add-on baseline as the RKE2 module is installed by default; set
`install_platform_addons = false` for a bare cluster.

## Mapping to AKS / GKE

This blueprint deliberately mirrors the structure of
[aks-platform](https://github.com/SriLingala/aks-platform) so platform teams
that run hybrid estates do not maintain two mental models.

| Concern              | AKS / GKE                           | RKE2 / k3s on-prem                  |
|----------------------|-------------------------------------|-------------------------------------|
| Cluster lifecycle    | Cloud control plane                 | Rancher Manager or terraform apply  |
| Node pools           | VM scale sets                       | Terraform-managed VMs or bare metal |
| Identity for pods    | Workload Identity (AAD federated)   | Vault Agent Injector + SPIFFE       |
| Secrets              | Key Vault CSI driver                | HashiCorp Vault + CSI driver        |
| Ingress              | Application Gateway or NGINX        | NGINX Ingress + MetalLB             |
| Storage              | Azure Disk / Files                  | Longhorn or Ceph                    |
| Logging              | Loki + Grafana                      | Loki + Grafana (same)               |
| Metrics              | Prometheus + Grafana                | Prometheus + Grafana (same)         |
| GitOps               | Argo CD                             | Argo CD (same)                      |
| Policy               | OPA Gatekeeper                      | OPA Gatekeeper (same)               |

The right-hand column is intentionally consistent with the left. That is the
point: developers do not need to know which cluster their workload lands on.

## Before you run this in production

A blueprint is the wiring, not the whole house. Read these before any
real workload lands:

- [docs/REMOTE-STATE.md](docs/REMOTE-STATE.md) — wire a remote backend; do
  not run with local state.
- [docs/BACKUP.md](docs/BACKUP.md) — etcd snapshots, Velero, and the
  restore drill cadence the platform team owns.
- [docs/AIR-GAPPED.md](docs/AIR-GAPPED.md) — registry mirrors, chart
  rendering, offline RKE2 install.

## Status

This is a starter skeleton. The Terraform modules install RKE2 / k3s plus
the platform add-on baseline and are CI-validated (`terraform fmt`,
`terraform validate`, `helm lint`), but the modules have not been exercised
against every supported provider. The pattern, directory layout and add-on
mapping are real and reflect how I would structure this work in a
production setting.

## Licence

MIT.
