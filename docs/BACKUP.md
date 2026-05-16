# Backup & disaster recovery

The blueprint installs the runtime but **does not** install a backup tier.
On bare-metal Kubernetes you own restore RTO/RPO end-to-end, so this is
deliberately a per-site decision. Below is the shape the platform team
should fill in before any workloads land on the cluster.

## Three things to back up

| Tier             | What                                                         | Tool                                  | RPO target |
|------------------|--------------------------------------------------------------|---------------------------------------|------------|
| Control plane    | etcd snapshots (RKE2 already takes these; verify retention)  | `rke2 etcd-snapshot save` + offsite copy | 1 hour     |
| Cluster objects  | All non-stateful k8s resources (Deployments, ConfigMaps, RBAC, CRDs) | Velero                               | 1 hour     |
| Persistent data  | Stateful workload volumes                                    | Velero + CSI snapshots (Longhorn / Ceph RBD) | 1 hour     |

## etcd snapshots (RKE2)

RKE2 ships with etcd snapshotting on by default — every 12h, retained for
5 days, written to `/var/lib/rancher/rke2/server/db/snapshots/` on each
control-plane node. Two extra steps you almost certainly want:

1. **Push snapshots offsite.** A simple systemd timer that rsyncs
   `/var/lib/rancher/rke2/server/db/snapshots/` to your object store is
   enough. RKE2 also supports S3-compatible upload directly via
   `--etcd-s3` flags if you'd rather not maintain the timer.
2. **Test restore quarterly.** A snapshot you have never restored from is
   not a backup. Schedule a yearly DR exercise that brings a fresh control
   plane up from the latest snapshot.

## k3s

k3s uses sqlite by default and supports etcd when `--cluster-init` is set
(which this module does). Same snapshotting story applies — `k3s
etcd-snapshot save`. On single-node edge sites without HA, snapshotting
the entire `/var/lib/rancher/k3s/` directory plus your application PVs is
usually simpler than treating etcd separately.

## Velero

Velero handles both kubernetes object backup and CSI volume snapshots.
Suggested install (out of scope for this blueprint; install via Argo CD):

- Object store: same MinIO / Ceph RGW bucket as terraform state, separate
  prefix.
- Schedule: hourly for `default` and team namespaces, daily for system
  namespaces.
- Retention: 7 daily, 4 weekly, 6 monthly — match your compliance window.

## Things that frequently break restores

- **CRDs.** Velero needs the CRDs installed before it can restore CRs.
  Order matters; Velero handles this if you let it install in priority
  order, but custom hooks can break it.
- **External secrets.** If you use external-secrets / Vault, the actual
  secret material lives off-cluster. Back that up separately.
- **Stateful workloads with anti-affinity.** A restored Deployment with
  podAntiAffinity may not schedule on a smaller restore cluster. Test.
- **Persistent volume reclaim policy.** Set to `Retain` for tier-1 data so
  a botched namespace delete does not also wipe the underlying disk.
