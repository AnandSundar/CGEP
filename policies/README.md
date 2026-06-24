# Compliance Policies

This directory contains Rego policies for the CGEP (Cloud Governance Evidence
Platform) compliance pipeline. Each policy targets a NIST SP 800-53 control
and is evaluated against a Terraform plan (`terraform/plan.json`) produced by
`terraform show -json tfplan`.

## Policies

Seven files, four control IDs, two clouds. The original three target **GCP**
(`google_storage_bucket` / `google_compute_*`); the three `_aws.rego` variants
target **AWS** (`aws_s3_bucket` / `aws_s3_bucket_public_access_block` /
`aws_s3_bucket_server_side_encryption_configuration`). The seventh — `au2_`
— targets the GCP `google_project_iam_audit_config` resources introduced by
Lab 5.4.

| Control | Cloud | Severity | File | Package |
|---------|-------|----------|------|---------|
| AC-3 | GCP | critical | [`ac3_no_public.rego`](./ac3_no_public.rego) | `compliance.ac3` |
| AC-3 | AWS | critical | [`ac3_no_public_aws.rego`](./ac3_no_public_aws.rego) | `compliance.ac3_aws` |
| AU-2 | GCP | high | [`au2_data_access_logs_gcp.rego`](./au2_data_access_logs_gcp.rego) | `compliance.au2_gcp` |
| CM-6 | GCP | medium | [`cm6_required_tags.rego`](./cm6_required_tags.rego) | `compliance.cm6` |
| CM-6 | AWS | medium | [`cm6_required_tags_aws.rego`](./cm6_required_tags_aws.rego) | `compliance.cm6_aws` |
| SC-28 | GCP | high | [`sc28_encryption.rego`](./sc28_encryption.rego) | `compliance.sc28` |
| SC-28 | AWS | high | [`sc28_encryption_aws.rego`](./sc28_encryption_aws.rego) | `compliance.sc28_aws` |

The policy gate ([`scripts/policy-gate.sh`](../scripts/policy-gate.sh))
evaluates the four AWS-targeted namespaces against any `plan.json` produced
by `terraform show -json tfplan`, plus the GCP `compliance.cm6` and
`compliance.au2_gcp` namespaces for Lab 5.4 coverage.

---

### AC-3 — Access Enforcement

- **Control ID:** AC-3
- **Framework:** NIST SP 800-53
- **Severity:** critical
- **File:** [`ac3_no_public.rego`](./ac3_no_public.rego)
- **What it covers:** GCS buckets must enforce
  `uniform_bucket_level_access = true` and
  `public_access_prevention = "enforced"`. Compute firewall ingress rules
  must not allow `0.0.0.0/0` (or `*`) on management ports `22` (SSH) or
  `3389` (RDP).
- **Remediation:** Set `uniform_bucket_level_access = true` and
  `public_access_prevention = "enforced"` on every `google_storage_bucket`.
  For `google_compute_firewall` rules, narrow `source_ranges` to a private
  CIDR or remove the management-port rule.
- **Tests:** [`tests/ac3_no_public_test.rego`](./tests/ac3_no_public_test.rego)
  covers a compliant bucket, a public bucket, and a firewall with port 22
  open to the world.

### CM-6 — Configuration Settings

- **Control ID:** CM-6
- **Framework:** NIST SP 800-53
- **Severity:** medium
- **File:** [`cm6_required_tags.rego`](./cm6_required_tags.rego)
- **What it covers:** Every taggable resource (`google_storage_bucket`,
  `google_compute_instance`, `google_compute_disk`) must carry the four
  required labels: `project`, `environment`, `managed_by`,
  `compliance_scope`.
- **Remediation:** Add the four required labels to the `labels` block of
  every labelable resource.
- **Tests:** [`tests/cm6_required_tags_test.rego`](./tests/cm6_required_tags_test.rego)
  covers a fully-labeled resource, a partially-labeled resource, and a
  resource with no labels at all.

---

### AU-2 — Data Access Audit Logs (GCP)

- **Control ID:** AU-2
- **Framework:** NIST SP 800-53
- **Severity:** high
- **File:** [`au2_data_access_logs_gcp.rego`](./au2_data_access_logs_gcp.rego)
- **What it covers:** Every required GCP service must have a
  `google_project_iam_audit_config` with `DATA_READ`, `DATA_WRITE`,
  and `ADMIN_READ` enabled. Lab 5.4 requires this for
  `storage.googleapis.com`, `cloudkms.googleapis.com`, and
  `iam.googleapis.com`. Data Access logs are off by default in GCP —
  this gate catches a silent regression.
- **Remediation:** Add a `google_project_iam_audit_config` resource
  for each missing service, with three `audit_log_config { log_type = ... }`
  blocks (`DATA_READ`, `DATA_WRITE`, `ADMIN_READ`). See
  [`terraform/baselines/gcp/audit_logs.tf`](../terraform/baselines/gcp/audit_logs.tf)
  for the canonical implementation.
- **Tests:** [`tests/au2_data_access_logs_gcp_test.rego`](./tests/au2_data_access_logs_gcp_test.rego)
  covers a fully-compliant baseline, a missing-service scenario, a
  partial-log-types regression, and a completely-empty input.

### SC-28 — Protection of Information at Rest

- **Control ID:** SC-28
- **Framework:** NIST SP 800-53
- **Severity:** high
- **File:** [`sc28_encryption.rego`](./sc28_encryption.rego)
- **What it covers:** Every `google_storage_bucket` must encrypt at rest
  with a customer-managed encryption key (CMEK) — i.e. an
  `encryption { default_kms_key_name = ... }` block referencing a
  `google_kms_crypto_key` under the project's control.
- **Remediation:** Add an `encryption { default_kms_key_name = ... }` block
  to the bucket, pointing at a `google_kms_crypto_key` you control.
- **Tests:** [`tests/sc28_encryption_test.rego`](./tests/sc28_encryption_test.rego)
  covers a bucket with a populated CMEK and a bucket with no encryption
  block.

---

## Usage

Run the unit-test suite:

```sh
opa test policies/
```

Evaluate a Terraform plan against a single policy:

```sh
opa eval -d policies -i terraform/plan.json data.compliance.<policy>.deny --format=pretty
```

The CI pipeline runs all three policies against `terraform/plan.json` and
fails the build if any `deny` set is non-empty.
