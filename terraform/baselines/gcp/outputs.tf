# terraform/baselines/gcp/outputs.tf
# Lab 5.4 — values for verification + CI configuration

output "gcp_project" {
  description = "Project ID the baseline was applied to."
  value       = var.gcp_project
}

output "wif_pool_name" {
  description = "Full resource name of the WIF pool."
  value       = google_iam_workload_identity_pool.github.name
}

output "wif_provider_name" {
  description = "Full resource name of the WIF provider. Paste this into google-github-actions/auth's workload_identity_provider input (or expose as a repo variable, e.g. GCP_WIF_PROVIDER)."
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "service_account_email" {
  description = "Email of the service account that GitHub Actions impersonates. Paste this into google-github-actions/auth's service_account input (or expose as a repo variable, e.g. GCP_WIF_SA_EMAIL)."
  value       = google_service_account.gha.email
}

# NOTE: Org Policy constraints are NOT managed at the project level by this
# baseline. They are inherited from org-level policies (org 1091529628888
# enforces storage.uniformBucketLevelAccess and
# iam.disableServiceAccountKeyCreation; compute.requireOsLogin is not set
# anywhere). For lab reproducibility on a fresh project under an org
# without these policies, add a `terraform/baselines/gcp/org_policy.tf`
# with three google_org_policy_policy resources. The compliance gate
# (compliance.au2_gcp) does not depend on these resources — it gates on
# the audit config resources below.
output "org_policy_inheritance_note" {
  description = "Org Policies are inherited from org level, not managed here. See README.md."
  value       = "Inherited from org 1091529628888; project-level overrides blocked by 'orgpolicy.policies.create' permission anomaly."
}

output "audit_config_services" {
  description = "GCP services with Data Access audit logs enabled by this baseline."
  value = [
    google_project_iam_audit_config.storage.service,
    google_project_iam_audit_config.kms.service,
    google_project_iam_audit_config.iam.service,
  ]
}
