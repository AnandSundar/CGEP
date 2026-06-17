# Compliance Policies

This directory contains Rego policies for the CGEP (Cloud Governance Evidence
Platform) compliance pipeline. Each policy targets a NIST SP 800-53 control
and is evaluated against a Terraform plan (`terraform/plan.json`) produced by
`terraform show -json tfplan`.

## Policies

| Control | Severity | File | Package |
|---------|----------|------|---------|
| [AC-3](#ac-3--access-enforcement) | critical | [`ac3_no_public.rego`](./ac3_no_public.rego) | `compliance.ac3` |
| [CM-6](#cm-6--configuration-settings) | medium | [`cm6_required_tags.rego`](./cm6_required_tags.rego) | `compliance.cm6` |
| [SC-28](#sc-28--protection-of-information-at-rest) | high | [`sc28_encryption.rego`](./sc28_encryption.rego) | `compliance.sc28` |

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
