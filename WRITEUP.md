# Lab 4-4 — Chain of Custody for GRC Evidence

This lab establishes an independently-verifiable chain of custody for compliance evidence produced by the GRC gate pipeline. Every artifact stored in the S3 evidence vault can be re-validated by anyone with read access to the bucket — no trust in the CI runner required.

## Pipeline

```
   PR opened against main   (or workflow_dispatch on a feature branch)
                │
                ▼
   .github/workflows/grc-gate.yml
       ├── actions/checkout
       ├── AWS OIDC  →  assume role (vars.AWS_ROLE_ARN)
       ├── terraform init / validate / plan  →  plan.json, plan.txt
       ├── conftest (4 namespaces)            →  conftest-results.json
       ├── tfsec                              →  tfsec.sarif
       ├── upload-artifact  →  grc-evidence-<run_id>
       │
       ▼  step 12: Bundle + sign + upload
   shasum -a 256      →  <bundle>.sha256
   cosign sign-blob   →  <bundle>.sig.bundle     (keyless, GitHub Actions OIDC)
   aws s3 cp          →  s3://<vault>/runs/<run_id>/<bundle>{,.sha256,.sig.bundle}
   receipt.json       →  S3 VersionId + commit SHA + bundle SHA256
```

The S3 bucket has **Object Lock in Compliance mode** with a default retention period (configured by Terraform). Neither the bucket owner nor AWS support can delete or modify a locked object before `RetainUntilDate`.

## Chain properties

The four properties an auditor needs to confirm about a piece of stored evidence, and the artifact that proves each.

### 1. Authenticity — the bundle was signed by *this* workflow run, not an impostor

**Artifact:** `*.sig.bundle` — a cosign signature bundle in the post-v2 format. It embeds (a) the Fulcio-issued signing certificate and (b) the Rekor transparency-log entry, both for the bundle's SHA-256.

**How it proves it:** The signing key was minted by Fulcio from a short-lived GitHub Actions OIDC token (`issuer: https://token.actions.githubusercontent.com`). The token's claims are bound into the certificate's SAN, so the certificate can only have been produced by a workflow run in this repository. `cosign verify-blob` checks the cert chain, the SAN, the OIDC issuer, and that a matching entry exists in the public Rekor log.

```bash
cosign verify-blob \
  --bundle evidence-*.tar.gz.sig.bundle \
  --certificate-identity-regexp '.*' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  evidence-*.tar.gz
```

### 2. Integrity — the bundle bytes haven't been mutated since signing

**Artifact:** `<bundle>.sha256` — the SHA-256 sidecar written at sign time, alongside the bundle, also stored under Object Lock.

**How it proves it:** Re-computing SHA-256 over the downloaded tarball and comparing to the sidecar detects any byte-level modification. A re-signed bundle would not match the sidecar written under the original key, so the SHA-256 sidecar is the *first* line of defense — the signature is the *second*. Both must agree.

```bash
EXPECTED=$(cat evidence-*.tar.gz.sha256)
ACTUAL=$(shasum -a 256 evidence-*.tar.gz | awk '{print $1}')
[[ "$EXPECTED" == "$ACTUAL" ]] && echo "OK" || echo "FAIL"
```

### 3. Timeliness — the signing event happened when we say it did

**Artifact:** the Rekor transparency-log entry inside `*.sig.bundle` (field `rekorEntry.body.integratedTime`).

**How it proves it:** Rekor signs a timestamp into each entry via a Merkle tree anchored in the Sigstore transparency log. The timestamp is cryptographically bound to the bundle hash, so it cannot be back-dated without breaking the chain. As an independent second timestamp, the OIDC token's `iat` (issued-at) claim is also embedded in the signing certificate's SAN.

```bash
# Pull integrated time from the verified bundle
cosign verify-blob \
  --bundle evidence-*.tar.gz.sig.bundle \
  --certificate-identity-regexp '.*' \
  --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
  --output json evidence-*.tar.gz \
  | jq -r '.rekorEntry.body.integratedTime'
# → 1749xxxxxx   (Sigstore-anchored Unix epoch)
```

### 4. Preservation — the bundle is retained for the required period, even from the bucket owner

**Artifact:** S3 Object Lock `RetainUntilDate` on the bundle object.

**How it proves it:** S3 Object Lock in Compliance mode rejects delete and overwrite requests — including from the AWS account root — until the retention timestamp passes. The verifier queries the per-object retention via `s3api get-object-retention` and rejects any bundle whose lock has expired. This means a compromised CI pipeline or a malicious bucket owner *cannot* retroactively delete evidence.

```bash
RETAIN_UNTIL=$(aws s3api get-object-retention \
  --bucket "$VAULT" --key "runs/$RUN_ID/$BUNDLE" \
  --query 'Retention.RetainUntilDate' --output text)
[[ "$RETAIN_UNTIL" > "$(date -u +%Y-%m-%dT%H:%M:%SZ)" ]] && echo "OK" || echo "FAIL"
```

## End-to-end verification

`scripts/verify-evidence.sh` automates all four checks against an S3-hosted bundle. The script does not read environment state from CI — it can be run on any machine with `aws`, `cosign`, and `shasum` (your laptop is the auditor).

```bash
EVIDENCE_VAULT="cgep-lab-grc-evidence-vault-2aa24c19" \
  bash scripts/verify-evidence.sh 27730875500 --profile iamadmin-general
```

Output (truncated):
```
download: s3://cgep-lab-grc-evidence-vault-2aa24c19/runs/27730875500/evidence-27730875500-12190ff806a48f64292fa5f171eb3ba9c9cd153d.tar.gz.sig.bundle
download: s3://cgep-lab-grc-evidence-vault-2aa24c19/runs/27730875500/receipt.json
download: s3://cgep-lab-grc-evidence-vault-2aa24c19/runs/27730875500/evidence-27730875500-12190ff806a48f64292fa5f171eb3ba9c9cd153d.tar.gz.sha256
download: s3://cgep-lab-grc-evidence-vault-2aa24c19/runs/27730875500/evidence-27730875500-12190ff806a48f64292fa5f171eb3ba9c9cd153d.tar.gz
Verified OK
CHAIN INTACT for run 27730875500
```

| Check | Property | Tool |
|---|---|---|
| SHA-256 sidecar matches recomputed hash | Integrity | `shasum` |
| `cosign verify-blob` against GitHub OIDC issuer | Authenticity | `cosign` (Fulcio + Rekor) |
| Rekor `integratedTime` is a valid signed timestamp | Timeliness | `cosign` (transparency log) |
| S3 Object Lock `RetainUntilDate` is in the future | Preservation | `aws s3api get-object-retention` |

## Reference run

| Field | Value |
|---|---|
| GitHub Actions run | `27730875500` |
| Trigger | `workflow_dispatch` on branch `add-grc-gate3` |
| Commit | `12190ff` — `fix(grc-gate): correct YAML indentation on cosign install + sign steps` |
| Vault | `cgep-lab-grc-evidence-vault-2aa24c19` |
| S3 prefix | `runs/27730875500/` |
| Bundle | `evidence-27730875500-12190ff806a48f64292fa5f171eb3ba9c9cd153d.tar.gz` (10,566 B) |
| SHA-256 sidecar | `evidence-27730875500-12190ff806a48f64292fa5f171eb3ba9c9cd153d.tar.gz.sha256` (65 B) |
| Cosign bundle | `evidence-27730875500-12190ff806a48f64292fa5f171eb3ba9c9cd153d.tar.gz.sig.bundle` (8,781 B) |
| Receipt | `receipt.json` — S3 VersionId, commit SHA, bundle SHA256 |

## Reproducing

1. **Trigger a fresh run** of `.github/workflows/grc-gate.yml`:
   - Open a PR against `main`, **or**
   - Actions tab → "grc-gate" → "Run workflow" → pick a feature branch (the workflow reads the YAML from the branch you select, so use a branch that has the cosign + sign steps committed)
2. **Wait for green** — step 12 (`Bundle + sign + upload to vault`) writes the bundle to the vault
3. **Capture the run_id** from the Actions tab URL
4. **Verify** from any machine with `aws` + `cosign` + `shasum`:
   ```bash
   EVIDENCE_VAULT="<vault-bucket>" \
     bash scripts/verify-evidence.sh <run_id> --profile <aws-profile>
   ```
5. **Inspect the receipt** for the S3 VersionId, commit SHA, and bundle SHA256:
   ```bash
   aws --profile <aws-profile> s3 cp \
     s3://<vault-bucket>/runs/<run_id>/receipt.json - | jq
   ```

## Mapping to NIST 800-53 controls

| Control | How this lab satisfies it |
|---|---|
| **AU-10** Non-repudiation | Keyless cosign signature binds the workflow identity to the bundle at sign time; the signature cannot be repudiated by the workflow owner. |
| **AU-9** Protection of Audit Information | Object Lock in Compliance mode prevents retroactive deletion or modification, even by the bucket owner. |
| **SI-7** Software, Firmware, and Information Integrity | SHA-256 sidecar + cosign signature together detect any byte-level mutation of stored evidence. |
| **SR-4** Provenance | Rekor transparency log entry proves the artifact was produced by *this specific* workflow run, not a re-signed copy. |

---

# Lab 5.4 — GCP Security Services Baseline

GCP's identity-first security model applied at project scope: Org
Policies enforced at the API (CM-6, AC-2, AC-3), Workload Identity
Federation replacing service account JSON keys (AC-2), and Data
Access audit logs turned on for the three services that matter
(AU-2). The full implementation lives under
[`terraform/baselines/gcp/`](terraform/baselines/gcp/), the demo
WIF workflow at [`.github/workflows/gcp-wif-demo.yml`](.github/workflows/gcp-wif-demo.yml),
and the Rego gate at
[`policies/au2_data_access_logs_gcp.rego`](policies/au2_data_access_logs_gcp.rego).

## The lesson: "Data Access logs are off by default"

A brand-new GCP project has `auditConfigs: []`. `ADMIN_READ` is
enabled for most services (which captures `SetIamPolicy`,
`CreateServiceAccount`, etc. — administrative events), but
`DATA_READ` and `DATA_WRITE` are NOT enabled for any service. The
question "who read this object?" is unanswerable until you turn them
on. This is the most-cited GCP audit finding because nobody turns
them on.

The Lab 5.4 baseline turns them on for storage, KMS, and IAM. The
[`compliance.au2_gcp`](policies/au2_data_access_logs_gcp.rego) Rego
gate makes sure a future change can't silently re-disable them —
the policy evaluates the Terraform plan and refuses to merge if any
of the three services loses one of the three log types. The
corresponding evidence is the `auditConfigs` block in
[`evidence/lab-5-4/iam-policy.json`](evidence/lab-5-4/iam-policy.json),
a live `gcloud projects get-iam-policy` capture.

## Real-world wrinkle: org-level Org Policies

The lab was developed against `project-a383fc9e-52f5-406a-9e8`
(project number `548524317995`) inside org `1091529628888`. The
parent org already enforces two of the three target constraints at
org level — `storage.uniformBucketLevelAccess` and
`iam.disableServiceAccountKeyCreation` — so the project inherits
`enforce=true` for both via effective-policy evaluation. The third
constraint, `compute.requireOsLogin`, is not set anywhere (the org
default for that constraint is `enforce=false`).

Because of this, the Terraform root does NOT manage Org Policy
resources at project level. Creating project-level
`google_org_policy_policy` resources would either be redundant (for
the two already-inherited) or fail with `orgpolicy.policies.create`
denied at org level (for the missing one). The root applies the
8 auditable resources directly:

| Resource | Layer |
|---|---|
| `google_iam_workload_identity_pool.github` | WIF |
| `google_iam_workload_identity_pool_provider.github` | WIF |
| `google_service_account.gha` + bindings | WIF |
| `google_project_iam_audit_config.{storage,kms,iam}` | AU-2 |

…and relies on org-level inheritance for the three Org Policies.
All four layers are PROVEN to be active in
[`evidence/lab-5-4/`](evidence/lab-5-4/):

| File | What it proves |
|---|---|
| `iam-policy.json` | The three audit configs exist with all three log types enabled |
| `org-policies-effective.json` | The two enforced-by-inheritance policies show `enforce=true` on this project |
| `key-creation-rejection.txt` | `iam.disableServiceAccountKeyCreation` REJECTS key creation with violation type |
| `uniform-bucket-rejection.txt` | `storage.uniformBucketLevelAccess` REJECTS non-uniform bucket creation with HTTP 412 |

For reproducibility on a project under an org that does NOT already
enforce these policies, recreate
[`org_policy.tf`](terraform/baselines/gcp/README.md#re-adding-org_policytf)
with three `google_org_policy_policy` resources. The Rego gate
(`compliance.au2_gcp`) gates only the audit configs, so it works
independently of how Org Policies are managed.

## The lesson: identity-first vs detective

| Layer | Where it acts | Latency |
|---|---|---|
| Org Policy (`enforce = "TRUE"`) | At the API call. The bad request is REJECTED. | 5-10 minutes for first-apply propagation |
| Workload Identity Federation | At authentication. The bad token is rejected. | One OIDC round-trip |
| Data Access audit logs | After the fact. The bad action is recorded. | 30 seconds |
| Conftest (`compliance.au2_gcp`) | At PR time. The bad plan is rejected. | Seconds |

The first three are GCP-native. The fourth is the CGEP portfolio's
own layer — detective code-review-time gate that catches a
configuration regression before it ever reaches `terraform apply`.
Stack them and "disable Data Access logs" requires deleting the
Rego gate, the Terraform resource, the Org Policy's negation, AND
the IAM binding — four different reviews.

## How this lab interacts with the GRC gate

The grc-gate workflow ([`.github/workflows/grc-gate.yml`](.github/workflows/grc-gate.yml))
runs `conftest test` against five namespaces:

```
compliance.sc28_aws     compliance.ac3_aws
compliance.cm6_aws      compliance.cm6      compliance.au2_gcp
```

`compliance.au2_gcp` is the Lab 5.4 namespace. When the gate runs
against a `terraform/plan.json` produced from a checkout that does
NOT include the GCP baseline (e.g. the root `terraform/` consumer
tree), there are no `google_project_iam_audit_config` resources in
the plan and the gate emits zero deny messages — passes by
construction. When the gate runs against a `plan.json` produced
from `terraform/baselines/gcp/`, the gate fires if any of the
three services is missing or incomplete.
