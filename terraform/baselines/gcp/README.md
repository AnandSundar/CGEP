# terraform/baselines/gcp — Lab 5.4

GCP-native security services baseline. Three layers, all in one Terraform
root, all at project scope (so it works in standalone projects that
don't sit inside an Organization):

1. **Org Policy** — `enforce = "TRUE"` rejects non-compliant API calls
   before the resource is created. This is prevention, not detection.
2. **Workload Identity Federation** — replaces long-lived service account
   JSON keys with short-lived OIDC tokens minted by GitHub Actions.
3. **Data Access audit logs** — per-service, off by default in GCP. This
   is the most-cited GCP audit finding because nobody turns them on.

## Controls mapped

| Layer | Resource | Controls |
|-------|----------|----------|
| Org Policy — `storage.uniformBucketLevelAccess = TRUE` | `google_org_policy_policy.uniform_bucket_access` | CM-6 |
| Org Policy — `iam.disableServiceAccountKeyCreation = TRUE` | `google_org_policy_policy.disable_sa_keys` | AC-2 |
| Org Policy — `compute.requireOsLogin = TRUE` | `google_org_policy_policy.require_oslogin` | AC-3 |
| WIF pool + provider | `google_iam_workload_identity_pool.github` + provider | AC-2 (credential lifecycle) |
| WIF service account | `google_service_account.gha` + `google_project_iam_member.gha_viewer` | AC-2, AC-6 |
| WIF federated identity binding | `google_service_account_iam_binding.wif_user` | AC-2 |
| Data Access logs — storage | `google_project_iam_audit_config.storage` | AU-2 |
| Data Access logs — KMS | `google_project_iam_audit_config.kms` | AU-2 |
| Data Access logs — IAM | `google_project_iam_audit_config.iam` | AU-2, AU-12 |

## Why identity-first

GCP's bet is that the smallest unit of security is the principal, not
the resource. The two pieces that make whole categories of attack
uneconomical:

- **Org Policy enforces at the API call.** A bucket creation attempt
  that violates `uniformBucketLevelAccess` is REJECTED — not flagged
  in Security Hub three hours later. Lab 5.2's AWS equivalent
  (Config + Security Hub) is detective; this is preventative.
- **WIF replaces "create a service account, download a JSON key,
  paste into GitHub Secrets, hope nobody leaks it" with "the GitHub
  Actions runtime presents an OIDC token, GCP swaps it for a
  short-lived access token, the token expires automatically."** The
  Org Policy `iam.disableServiceAccountKeyCreation = TRUE` closes
  the key-creation door behind it.

## File layout

```
terraform/baselines/gcp/
├── main.tf                 # provider + required_providers (ADC)
├── variables.tf            # gcp_project, gcp_region, github_org_repo, ...
├── outputs.tf              # WIF provider name + SA email for CI config
├── org_policy.tf           # 3 google_org_policy_policy resources
├── workload_identity.tf    # pool, provider, SA, IAM binding
├── audit_logs.tf           # 3 google_project_iam_audit_config resources
└── README.md               # this file
```

Mirrors the split style of `terraform/baselines/aws/` (Lab 5.2):
`cloudtrail.tf` / `security_hub.tf` / `main.tf`. Same idea, different
cloud.

## Prerequisites

- A GCP project you own, with billing enabled.
- APIs enabled in that project:
  `gcloud services enable cloudkms.googleapis.com iam.googleapis.com cloudresourcemanager.googleapis.com orgpolicy.googleapis.com`
- Roles on the principal running `terraform apply` (project scope):
  - `roles/orgpolicy.policyAdmin` — to manage the three org policies
  - `roles/iam.workloadIdentityPoolAdmin` — for the WIF pool + provider
  - `roles/iam.serviceAccountAdmin` — to create the SA
  - `roles/resourcemanager.projectIamAdmin` — for `google_project_iam_member`
  - `roles/logging.admin` — for the three `google_project_iam_audit_config`
- `gcloud auth application-default login` (the `google` provider uses
  ADC; no JSON key file is read by Terraform).
- Terraform ≥ 1.6.

## Why no service account JSON key

The lab's WIF pattern is the AWS-OIDC equivalent. If this lab's demo
workflow (`.github/workflows/gcp-wif-demo.yml`) carried a JSON key,
every part of the lab would be undermined — including the
Org Policy that *forbids* key creation. Search the repo for
`credentials_json`, `gcp_service_account_key`, `GOOGLE_APPLICATION_CREDENTIALS`,
and `*.json` under `.github/workflows/`; none of them exist.

## Data Access logs are off by default — the #1 GCP audit finding

This is the lesson the lab walks explicitly. Default audit config
on a brand-new project is:

```
auditConfigs: []   (none)
```

`ADMIN_READ` is enabled for most services (which captures
SetIamPolicy, CreateServiceAccount, etc. — administrative events).
`DATA_READ` and `DATA_WRITE` are NOT enabled for any service —
which means the "who read this object?" question is unanswerable
until you turn them on.

This baseline turns them on for the three services the lab cares
about: storage, KMS, IAM. The Conftest gate
(`policies/au2_data_access_logs_gcp.rego`) makes sure a future
change can't silently re-disable them — the policy evaluates the
Terraform plan and refuses to merge if any of the three services
loses one of the log types.

## Captured evidence

The lab requires `evidence/lab-5-4/iam-policy.json` — the output of
`gcloud projects get-iam-policy` against the project, capturing
the `auditConfigs` block. See `evidence/lab-5-4/expected-evidence.md`
for the full capture procedure.

## Usage

```sh
cd terraform/baselines/gcp
terraform init
terraform plan -var "gcp_project=your-gcp-project"
terraform apply -auto-approve -var "gcp_project=your-gcp-project"
```

Then verify:

```sh
# Org Policies in effect
gcloud org-policies list --project=your-gcp-project \
  | grep -E "uniformBucket|disableServiceAccount|requireOsLogin"

# WIF pool exists
gcloud iam workload-identity-pools list --location=global \
  --project=your-gcp-project

# Data Access logs enabled (the iam-policy.json evidence file)
gcloud projects get-iam-policy your-gcp-project --format=json \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); \
      print(json.dumps(d.get("auditConfigs",[]), indent=2))'

# Try a forbidden action — expect FAILED_PRECONDITION
gcloud iam service-accounts keys create /tmp/k.json \
  --iam-account=cgep-grc-gate-sa@your-gcp-project.iam.gserviceaccount.com \
  --project=your-gcp-project
```

## Cleanup

`terraform destroy -auto-approve` removes everything this root created,
with two caveats from the lab walkthrough:

1. **WIF pools enter a 30-day soft-delete state.** They cannot be
   re-created with the same `workload_identity_pool_id` until the
   soft-delete expires or you `gcloud iam workload-identity-pools
   undelete <pool> --location=global` and then delete again with
   `--purge`.
2. **Disabling Org Policy enforcement does not retroactively
   un-enforce existing resources.** Buckets you created with
   uniform access stay that way; the policy just stops blocking
   new ones.

## How this feeds the capstone

The WIF pattern from this lab is your AWS-OIDC equivalent for any
GCP-touching workflow. If your capstone's pipeline reaches into GCP
for any reason, it uses WIF, not keys. The Org Policy enforcements
add a preventative layer above your Rego (which is detective). And
the Data Access logs feed your OSCAL component's AU-2 implementation
statement: enabled per-service, with the IAM policy JSON as evidence.