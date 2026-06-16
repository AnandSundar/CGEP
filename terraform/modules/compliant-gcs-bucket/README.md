# compliant-gcs-bucket

Terraform module that provisions a Google Cloud Storage bucket with a
customer-managed encryption key (CMEK) and security controls mapped to
NIST SP 800-53. Designed for GRC / evidence-collection workloads where
the configuration itself is the attestation.

## NIST 800-53 controls enforced

| Control   | Description                          | Implementation in `main.tf`                                                                                          |
|-----------|--------------------------------------|-----------------------------------------------------------------------------------------------------------------------|
| **SC-12** | Cryptographic key establishment      | `google_kms_key_ring` + `google_kms_crypto_key` — customer owns the key, not Google.                                 |
| **SC-13** | Use of cryptography                  | CMEK with AES-256. `rotation_period = "7776000s"` (90 days).                                                          |
| **SC-28** | Protection of information at rest    | `encryption { default_kms_key_name = ... }` + `versioning { enabled = true }`.                                        |
| **AU-11** | Audit record retention               | Object versioning + `retention_policy { retention_period = ... }`.                                                   |
| **CM-6**  | Configuration settings               | `uniform_bucket_level_access = true`, `public_access_prevention = "enforced"`.                                       |
| **AC-3**  | Access enforcement                   | Uniform bucket-level access disables legacy per-object ACLs; public access is hard-blocked.                           |

The module also emits a `compliance_attestation` output (see `output.tf`)
that re-reads the live state of every control, so an auditor can verify
what is actually in effect without reading the Terraform code or
visiting the GCP console.

## Lifecycle safety

The CMEK resource carries `lifecycle { prevent_destroy = false }` for
ergonomics in dev. **Set this to `true` in production** — a `terraform
destroy` against a key with active data would be catastrophic.

## Quickstart

```hcl
module "evidence" {
  source = "../../modules/compliant-gcs-bucket"

  gcp_project        = "my-gcp-project"
  project_label      = "cgep-lab"
  environment        = "dev"
  retention_days     = 30
  bucket_name_suffix = "evidence-001"
}
```

## Inputs

See `variables.tf`. All required inputs are validated; for example,
`retention_days < 365` is rejected when `environment = "prod"`.

## Outputs

See `output.tf`. The two most useful are:

- `bucket_url` — `gs://...` URL of the bucket.
- `compliance_attestation` — object describing each control's live state.
