# Edge and factory floor notes

Operating Kubernetes at the edge has different constraints to a datacentre.
This document captures the design choices that matter for trackside,
factory, or other constrained-environment deployments.

## k3s as the default for edge

k3s ships as a single binary, runs on ARM, and tolerates intermittent
connectivity. For trackside or factory environments where the cluster needs
to keep running when the link to head office goes down, k3s is the right
default.

Production characteristics worth knowing:

- Single binary install. SQLite backend by default. PostgreSQL or etcd for HA.
- Disables Traefik by default in this blueprint. Use NGINX Ingress instead for parity with cloud.
- Local-path provisioner for storage. Suitable when data is ephemeral. Use Longhorn if you need replication.

## Network design

Trackside and factory clusters typically sit behind NAT and connect back to
the central control plane over VPN, ExpressRoute, or a private link.

Three patterns:

1. **Central Argo CD with edge cluster Secrets.** Argo CD lives in the datacentre. Edge clusters register as Cluster resources. Drift detection happens centrally. Network must allow outbound from edge to central.

2. **Federated Argo CD.** Each edge cluster runs its own Argo CD. Central Argo CD ApplicationSet pushes app definitions. Each edge syncs from a Git mirror.  Best for true air-gapped edge.

3. **Pull-only edge.** Edge cluster pulls manifests from a Git repo on every interval. No reverse connection from central. Air-gap friendly. Slower drift correction.

I default to pattern 1 for trackside (intermittent but present link) and
pattern 3 for fully air-gapped factory environments.

## Update strategy

Edge clusters cannot be updated as casually as cloud. Each update is a risk
to a production event (race weekend, factory shift).

- Maintain a separate `edge-prod` and `edge-canary` Git branch.
- Promote from canary to prod only after the canary cluster has run the new platform version for 7 days without incident.
- Update during pre-race or factory-shutdown windows. Schedule via Argo CD sync windows.

## Hardware footprint

The k3s blueprint targets:

- Minimum: 4 GB RAM, 2 cores. Suitable for Raspberry Pi 5, industrial NUC, or a small VM on a control PC.
- Recommended for production edge: 8 GB RAM, 4 cores. SSD storage. ARM or x86.
- Avoid: anything less than 2 GB RAM. k3s server alone uses around 250 MB and you need headroom for workloads.

## Observability at the edge

Loki agents on every node ship to central Loki when connectivity is up.
Buffer locally during outages. Prometheus federation pulls a subset of
metrics from each edge cluster to a central Prometheus.

Do not try to scrape edge clusters from central Prometheus. The edge
network is unreliable and you will lose data. Push, do not pull.
