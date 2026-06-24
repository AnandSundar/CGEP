# Evidence — Lab 5.4

This directory collects the artifacts that prove the GCP security
baseline is in effect. Captured against `project-a383fc9e-52f5-406a-9e8`
(project number `548524317995`) on 2026-06-24.

## Files

| File | What it proves | How it was captured |
|---|---|---|
| `iam-policy.json` | The three `google_project_iam_audit_config` resources (storage/KMS/IAM) are applied — each with `DATA_READ`, `DATA_WRITE`, and `ADMIN_READ` enabled. | `gcloud projects get-iam-policy project-a383fc9e-52f5-406a-9e8 --format=json` |
| `org-policies-effective.json` | The two Org Policies (`storage.uniformBucketLevelAccess`, `iam.disableServiceAccountKeyCreation`) are ENFORCED at the project level via inheritance from org `1091529628888`. `compute.requireOsLogin` is the org default (`enforce=false`). | `gcloud org-policies describe ... --project=... --effective --format=json` |
| `key-creation-rejection.txt` | The `iam.disableServiceAccountKeyCreation` Org Policy is ACTIVE: `gcloud iam service-accounts keys create` returns `FAILED_PRECONDITION` with violation type `constraints/iam.disableServiceAccountKeyCreation`. | `gcloud iam service-accounts keys create /tmp/sa-key-evidence.json --iam-account=$SA` |
| `uniform-bucket-rejection.txt` | The `storage.uniformBucketLevelAccess` Org Policy is ACTIVE: REST API `storage.buckets.insert` with `iamConfiguration.uniformBucketLevelAccess.enabled=false` returns HTTP 412 with violation type `constraints/storage.uniformBucketLevelAccess`. | `curl -X POST .../storage/v1/b?project=$PROJECT_NUM` with `iamConfiguration.uniformBucketLevelAccess.enabled=false` |

## Capture procedure

### `iam-policy.json` (the lab's required evidence)

```sh
gcloud projects get-iam-policy project-a383fc9e-52f5-406a-9e8 --format=json \
  > evidence/lab-5-4/iam-policy.json
```

### `org-policies-effective.json`

```sh
for c in storage.uniformBucketLevelAccess iam.disableServiceAccountKeyCreation compute.requireOsLogin; do
  gcloud org-policies describe "$c" \
    --project=project-a383fc9e-52f5-406a-9e8 --effective --format=json
done
```

### `key-creation-rejection.txt`

```sh
# step 1: create a temporary SA (allowed; not blocked by any policy)
SA=$(gcloud iam service-accounts create "cgep-evidence-tmp" \
  --project=project-a383fc9e-52f5-406a-9e8 \
  --format='value(email)')

# step 2: try to create a JSON key for it — should be REJECTED
gcloud iam service-accounts keys create /tmp/sa-key.json \
  --iam-account="$SA" --project=project-a383fc9e-52f5-406a-9e8 \
  2> evidence/lab-5-4/key-creation-rejection.txt || true

# step 3: cleanup
gcloud iam service-accounts delete "$SA" \
  --project=project-a383fc9e-52f5-406a-9e8 --quiet
```

### `uniform-bucket-rejection.txt`

```sh
TOKEN=$(gcloud auth print-access-token)
BUCKET="cgep-evil-bucket-$(date +%s)"
PROJECT_NUM=548524317995

# violation attempt
curl -s -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"$BUCKET\",\"iamConfiguration\":{\"uniformBucketLevelAccess\":{\"enabled\":false}}}" \
  "https://storage.googleapis.com/storage/v1/b?project=$PROJECT_NUM"
# → HTTP 412 "Request violates constraint 'constraints/storage.uniformBucketLevelAccess'"
```

## Why the example.json was removed

The repo previously carried `iam-policy.example.json` as a placeholder
showing the expected shape. After the live `terraform apply` succeeded,
it was replaced with `iam-policy.json` (the real `gcloud` capture). The
shape is identical except for the project-specific Etag.

## README cross-references

The lessons in this evidence directory are documented in
[terraform/baselines/gcp/README.md](../../terraform/baselines/gcp/README.md):

- "Org Policy note" — why this root doesn't manage Org Policy resources
- "Data Access logs are off by default" — the AU-2 lesson

And in the portfolio writeup: [WRITEUP.md](../../WRITEUP.md) under
"Lab 5.4 — GCP Security Services Baseline".