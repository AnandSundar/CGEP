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

output "org_policy_constraints" {
  description = "Constraint names enforced by this baseline."
  value = {
    uniform_bucket_level_access          = google_org_policy_policy.uniform_bucket_access.name
    disable_service_account_key_creation = google_org_policy_policy.disable_sa_keys.name
    require_os_login                     = google_org_policy_policy.require_oslogin.name
  }
}

output "audit_config_services" {
  description = "GCP services with Data Access audit logs enabled by this baseline."
  value = [
    google_project_iam_audit_config.storage.service,
    google_project_iam_audit_config.kms.service,
    google_project_iam_audit_config.iam.service,
  ]
}
