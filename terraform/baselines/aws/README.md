# terraform/baselines/aws — Lab 5.2

AWS-native security services baseline. CloudTrail for the
"what happened" layer and Security Hub for the aggregated
"is it compliant right now" layer. AWS Config is intentionally
NOT included — it would fail an org-level `config:*` SCP in a
member account, and the absence is documented as the lab's
own evidence of the gap (see *Captured evidence* below).

## Controls mapped

| Service | Resource | Controls |
|---------|----------|----------|
| CloudTrail (multi-region, `enable_log_file_validation = true`) | `aws_cloudtrail.mgmt` | AU-2, AU-12, AU-10 |
| CloudTrail bucket SSE-S3 + public access block | `aws_s3_bucket.trail` + companions | AC-3, SC-28 |
| Security Hub hub (default, us-east-1) | `aws_securityhub_account.this` | RA-5, SI-4 |
| Security Hub standard — NIST 800-53 Rev 5 | `aws_securityhub_standards_subscription.nist_800_53` | AU-6, CA-7, CM-3, CM-6, SI-2 (subset) |
| Security Hub standard — AWS FSBP v1.0.0 | `aws_securityhub_standards_subscription.fsbp` | AWS-curated subset of NIST controls |

The four required CM-6 tags (`Project`, `Environment`, `ManagedBy`,
`ComplianceScope`) propagate to every taggable resource via the AWS
provider's `default_tags` block in `main.tf`. `policies/cm6_required_tags_aws.rego`
evaluates `aws_s3_bucket`, `aws_dynamodb_table`, `aws_lambda_function`,
`aws_kms_key`, and `aws_cloudtrail` — this baseline passes for all
five types.

## Why no AWS Config

The lab walkthrough includes Config in its reference Terraform
but the SCP deny `config:*` for non-management accounts will cause
`terraform apply` to return `AccessDeniedException: ... with an
explicit deny in a service control policy`. This account is the
organization's management account (o-1ss09qo5at) and is not subject
to that SCP, but Config is intentionally not enabled to keep the
baseline as a faithful reproduction of the member-account scenario
the lab walkthrough describes.

When Config is not enabled, the Security Hub control
`Config.1` (CRITICAL severity; related requirements
NIST.800-53.r5 CM-3, CM-6(1), CM-8, CM-8(2)) is enabled but
cannot produce a finding because it depends on Config data.
That inability-to-evaluate is itself the documented gap.

## Pre-existing state imported

| Resource | Imported from | Rationale |
|----------|---------------|-----------|
| `aws_securityhub_account.this` | account ID `348342704892` | Hub was already enabled 2026-04-02. `enable_default_standards = false` is pinned to match the current setting — the resource default (`true`) would force a destroy-recreate. |
| `aws_securityhub_standards_subscription.fsbp` | subscription ARN `arn:aws:securityhub:us-east-1:348342704892:subscription/aws-foundational-security-best-practices/v/1.0.0` | FSBP was already subscribed. Imported (not re-created) to avoid re-subscribing. |
| `aws_securityhub_standards_subscription.nist_800_53` | (n/a) | **New.** Created by this lab. |
| `aws_cloudtrail` (existing) | `Animals4lifeOrg` | Pre-existing trail (multi-region, `LogFileValidation: None`) is left untouched. This lab adds a separate `cgep-lab-mgmt` trail with `enable_log_file_validation = true` rather than retrofitting the existing one. |

## Captured evidence

`evidence/lab-5-2/security-hub-findings.json` is the captured Security
Hub findings set (449,908 bytes — 100 findings, the API max). 77 of
those are from the NIST 800-53 Rev 5 first wave that populated within
~10 minutes of subscribing the standard. Severity distribution
(INFORMATIONAL/MEDIUM/LOW — no CRITICAL or HIGH):

```
INFORMATIONAL : 48
MEDIUM        : 32
LOW           : 20
```

The bundle is signed and uploaded to the Lab 2.5 evidence vault
(`cgep-lab-grc-evidence-vault-2aa24c19`) by `scripts/capture-evidence.sh`.

| Artifact | Vault key | VersionId |
|----------|-----------|-----------|
| `terraform/baselines/aws/` bundle (plan, state, terraform version, commit, sha256 manifest, plus the three `*.json` evidence files) | `s3://cgep-lab-grc-evidence-vault-2aa24c19/runs/lab-5-2-2026-06-19/bundle.tar.gz` | `L27Rbw8SA7v8iJzjqCC5VtQ.FExroF_b` |

`evidence/lab-5-2/config1-control-status.json` records that the
`Config.1` control is `ENABLED` with `SeverityRating: CRITICAL` and
related requirements `NIST.800-53.r5 CM-3, CM-6(1), CM-8, CM-8(2)` —
but no finding has been produced because AWS Config is not enabled
in this account. The inability of the control to produce a finding
is itself the documented evidence of the gap.

`evidence/lab-5-2/cloudtrail-status.json` and
`evidence/lab-5-2/trail-bucket-inventory.txt` capture the trail's
first-hour state (IsLogging: true, 1 log file delivered, S3 inventory).

The local receipt is in `evidence/lab-5-2/receipt.json`.

## Usage

```sh
cd terraform/baselines/aws
terraform init
terraform plan
terraform apply -auto-approve
```

## Cleanup

The lab's pre-existing Security Hub account and FSBP subscription
must be left in place in AWS. `terraform state rm` alone is not
enough — once they're out of state, a plain `terraform destroy`
will see "in config, not in state" and try to RECREATE them,
which will fail with `ResourceConflictException`.

Use targeted destroys for the lab-created resources only, then
state-rm the imports:

```sh
cd terraform/baselines/aws

# Bring the pre-existing SH + FSBP back into state if they aren't
# already there (they get left out of state after a previous
# cleanup, or if this is a fresh checkout of the repo).
terraform import aws_securityhub_account.this 348342704892
terraform import aws_securityhub_standards_subscription.fsbp \
  "arn:aws:securityhub:us-east-1:348342704892:subscription/aws-foundational-security-best-practices/v/1.0.0"

# Destroy ONLY the lab-created resources.
terraform destroy -auto-approve \
  -target=random_id.suffix \
  -target=aws_s3_bucket.trail \
  -target=aws_s3_bucket_server_side_encryption_configuration.trail \
  -target=aws_s3_bucket_public_access_block.trail \
  -target=aws_s3_bucket_policy.trail \
  -target=aws_cloudtrail.mgmt \
  -target=aws_securityhub_standards_subscription.nist_800_53

# Drop the imports from state so this TF root stops managing them.
terraform state rm aws_securityhub_account.this
terraform state rm aws_securityhub_standards_subscription.fsbp
```

`force_destroy = true` on the trail bucket lets the destroy remove
the bucket even though CloudTrail has written log files into it.
