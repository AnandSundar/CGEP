# Evidence — Lab 5.4

This directory collects the artifacts that prove the GCP security
baseline is in effect. The portfolio submission checklist calls out
two of them; the rest are captured here for completeness.

## Files

| File | What it is | When it exists |
|---|---|---|
| `iam-policy.example.json` | Illustrative shape of the expected `auditConfigs` block. Replace with a live capture before submitting. | Always (placeholder) |
| `iam-policy.json` | Live `gcloud projects get-iam-policy` output. Captured AFTER `terraform apply`. | After apply |
| `org-policies.json` | Live `gcloud org-policies list` output (filtered). | After apply |
| `wif-pool.json` | `gcloud iam workload-identity-pools describe github-actions --location=global --format=json` | After apply |
| `key-creation-rejection.txt` | Captured stderr of `gcloud iam service-accounts keys create` — proves the Org Policy is REJECTING (not flagging, REJECTING) the action. | After apply + Org Policy propagation |
| `audit-log-read-evidence.json` | `gcloud logging read 'protoPayload.serviceName="storage.googleapis.com"'` — proves Data Access logs are actually flowing. | 30+ seconds after a `gsutil ls` |

## Capture procedure

Run these after `terraform apply -auto-approve` succeeds AND after
the 5-10 minute Org Policy propagation window. Save each command's
output into the matching file.

```sh
# 1. iam-policy.json — the lab's required evidence
gcloud projects get-iam-policy "$GCP_PROJECT" --format=json \
  > evidence/lab-5-4/iam-policy.json

# 2. org-policies.json — proves all three are ENFORCED
gcloud org-policies list --project="$GCP_PROJECT" --format=json \
  | jq '[.[] | select(.constraint | startswith("storage.uniform") or
                                     startswith("iam.disableService") or
                                     startswith("compute.requireOs"))]' \
  > evidence/lab-5-4/org-policies.json

# 3. wif-pool.json — proves the WIF pool exists with the right provider
gcloud iam workload-identity-pools describe github-actions \
  --location=global --project="$GCP_PROJECT" --format=json \
  > evidence/lab-5-4/wif-pool.json

# 4. key-creation-rejection.txt — the lesson itself, captured as proof
gcloud iam service-accounts keys create /tmp/should-not-exist.json \
  --iam-account="cgep-grc-gate-sa@${GCP_PROJECT}.iam.gserviceaccount.com" \
  --project="$GCP_PROJECT" \
  2> evidence/lab-5-4/key-creation-rejection.txt || true
grep -q "FAILED_PRECONDITION" evidence/lab-5-4/key-creation-rejection.txt \
  || echo "WARN: Org Policy has not propagated yet — retry in 5 minutes"

# 5. audit-log-read-evidence.json — proves the logs are actually flowing
gsutil ls "gs://${GCP_PROJECT}-test-bucket" || true
sleep 30  # log delivery latency
gcloud logging read \
  'protoPayload.serviceName="storage.googleapis.com" AND protoPayload.methodName=~"storage.objects.list"' \
  --limit=5 --format=json --project="$GCP_PROJECT" \
  > evidence/lab-5-4/audit-log-read-evidence.json
```

## Why the placeholder is here

The repo is committed without a real GCP project behind it; the
lab is run on a personal project. The `iam-policy.example.json`
documents the expected shape so a reviewer can confirm (a) the
expected three services are configured, (b) all three log types
appear for each, (c) the JSON shape matches `gcloud` output. The
real evidence capture is one `gcloud` command away and replaces
this file with a byte-identical structure but project-specific
Etag.

## README cross-references

The lesson "Data Access logs are off by default" is documented in
[terraform/baselines/gcp/README.md](../../terraform/baselines/gcp/README.md)
under the section of the same name.