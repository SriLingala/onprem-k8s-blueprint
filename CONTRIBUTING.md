# Contributing

Thanks for improving `onprem-k8s-blueprint`.

## Local Checks

Run these before opening a pull request:

```bash
terraform fmt -check -recursive

cd terraform/rke2
terraform init -backend=false
terraform validate

cd ../k3s
terraform init -backend=false
terraform validate

cd ../../helm/platform-addons
helm dependency update
helm lint .
helm template platform-addons . >/dev/null
```

## Guidelines

- Keep examples provider-agnostic unless the docs call out a specific target.
- Treat Terraform state as sensitive and avoid introducing new plaintext secret
  flows.
- Pin platform component versions deliberately.
- Update README/docs when changing bootstrap, backup, or air-gapped behavior.
- Prefer small, reviewable changes over large architecture rewrites.

