# Security Policy

This repository is a reference blueprint for on-prem Kubernetes. It includes
bootstrap automation and sample platform add-ons, but every production estate
needs its own threat model, network controls, and operational runbooks.

## Reporting a Vulnerability

Please report security issues privately before opening a public issue. Include:

- The affected Terraform module, Helm value, or document.
- Whether credentials, kubeconfigs, join tokens, or workload data can be exposed.
- Steps to reproduce or a minimal example.
- Suggested mitigation, if known.

## Production Guidance

- Use encrypted remote Terraform state with locking, strict RBAC, and backups.
- Rotate bootstrap tokens and kubeconfigs after initial cluster creation where
  your operating model allows it.
- Mirror install scripts, container images, and Helm charts into trusted
  internal registries for production and air-gapped environments.
- Enforce host-key verification for every SSH bootstrap path.
- Keep kubeconfigs and Terraform state out of source control.
- Review all chart values against your organization's baseline policies before
  installing into shared clusters.

