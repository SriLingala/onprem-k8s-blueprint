# Air-gapped operation notes

Banking back-office, defence, and some regulated factories run Kubernetes
in environments with no outbound internet. This document captures the
practical steps to make RKE2 and k3s work in that setting.

## Image mirroring

All container images must be reachable from an internal registry. RKE2 and
k3s both support a registry mirror config:

```yaml
# /etc/rancher/rke2/registries.yaml
mirrors:
  docker.io:
    endpoint:
      - "https://registry.internal.example.com"
  quay.io:
    endpoint:
      - "https://registry.internal.example.com"
configs:
  "registry.internal.example.com":
    auth:
      username: <user>
      password: <pass>
```

Harbor is the usual choice for the internal registry. Mirror the upstream
images at build time so the cluster only ever pulls from the trusted source.

## Helm chart mirroring

Argo CD can sync from a Git repo that contains rendered Kubernetes manifests
rather than pulling charts at runtime. Approach:

1. Render charts with `helm template` in CI.
2. Commit the rendered manifests to a Git repo.
3. Argo CD watches that Git repo.

This removes the runtime dependency on Helm chart repositories.

## RKE2 air-gapped install

```bash
# On a connected machine, download the artefacts:
curl -L https://github.com/rancher/rke2/releases/download/v1.30.3%2Brke2r1/rke2.linux-amd64.tar.gz -o rke2.tar.gz
curl -L https://github.com/rancher/rke2/releases/download/v1.30.3%2Brke2r1/rke2-images.linux-amd64.tar.zst -o rke2-images.tar.zst

# Transfer rke2.tar.gz and rke2-images.tar.zst to the air-gapped host.
# On the air-gapped host:
mkdir -p /var/lib/rancher/rke2/agent/images/
mv rke2-images.tar.zst /var/lib/rancher/rke2/agent/images/
tar -xzf rke2.tar.gz -C /usr/local/
systemctl enable rke2-server.service
systemctl start rke2-server.service
```

## Certificate management

`cert-manager` with Let's Encrypt requires outbound HTTP/HTTPS for the ACME
challenge. In an air-gapped environment, swap to:

- Internal certificate authority (Vault PKI or a corporate CA)
- `cert-manager` Issuer pointing at the internal CA
- Long-lived cluster certificates rotated on a schedule

## Logging and metrics off-cluster

If logs and metrics must leave the air-gapped network for central analysis,
the usual pattern is a one-way data diode or a controlled SFTP drop. Loki
and Prometheus both support remote-write to a downstream collector. Run
that collector on the boundary.

## Updates

Updates are the hardest part of air-gapped operation. Plan for:

- Quarterly platform update windows.
- Pre-staged update bundles tested in a non-air-gapped mirror environment first.
- Rollback procedure documented and tested every release.

The platform team owns the bundle. Tenants do not pull updates ad hoc.
