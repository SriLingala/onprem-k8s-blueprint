# Terraform remote state on-prem

The modules in this repo intentionally do not declare a backend so you can
plug them into whichever state store your estate already uses. **Do not run
these modules with the default local backend in production** — on-prem teams
typically need state to survive operator laptop loss and to lock against
concurrent applies.

## Recommended options

| Backend            | When to reach for it                                                        |
|--------------------|-----------------------------------------------------------------------------|
| Terraform Cloud / Enterprise | You already use TFC/TFE for cloud estates. Same workflow, no new infra. |
| HashiCorp Consul   | You already run Consul on-prem. Native locking via session API.            |
| S3-compatible (MinIO, Ceph RGW) | You run an internal object store. Pair with DynamoDB-compatible locking (or `dynamodb_table` against AWS for hybrid setups). |
| GitLab managed state | You use GitLab CI and want auth/locking via the same RBAC.                |

## Wiring a backend

Add a `backend.tf` file alongside `main.tf`. Example using S3-compatible
storage with MinIO and DynamoDB-compatible locking via a Consul KV shim is
out of scope; for the common case below uses MinIO + DynamoDB-emulating
locking.

```hcl
terraform {
  backend "s3" {
    bucket                      = "platform-tfstate"
    key                         = "onprem/rke2/dc1.tfstate"
    region                      = "main"
    endpoint                    = "https://minio.platform.internal"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
    encrypt                     = true
    # Optional: state locking through a DynamoDB-compatible service.
    dynamodb_table = "tfstate-locks"
  }
}
```

For Terraform Cloud / Enterprise:

```hcl
terraform {
  cloud {
    organization = "your-org"
    workspaces {
      name = "onprem-rke2-dc1"
    }
  }
}
```

## Things to lock down

- **Encryption at rest.** Backend store must be encrypted; Terraform state
  contains secrets in plain text (kubeconfigs, tokens, generated passwords).
- **Access control.** RBAC the state path so only the platform team can read.
- **Locking.** Use the backend's native locking — concurrent applies on the
  same workspace will corrupt state.
- **Versioning.** Turn on object versioning so an accidental destroy is
  recoverable.
- **State backups.** Snapshot the bucket / Consul KV on the same cadence as
  your other tier-0 stores.
