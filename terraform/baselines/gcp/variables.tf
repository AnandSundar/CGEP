# terraform/baselines/gcp/variables.tf
# Lab 5.4 — input variables

variable "gcp_project" {
  type        = string
  description = "GCP project ID where the security baseline is applied. Must be a project you own with billing enabled."
}

variable "gcp_region" {
  type        = string
  description = "Default GCP region for the provider (e.g. us-central1). Org Policy, WIF, and audit logs are global, but the provider needs a region."
  default     = "us-central1"
}

variable "project_name" {
  type        = string
  description = "Short project identifier, used in resource labels and the WIF pool display name."
  default     = "cgep"
}

variable "environment" {
  type        = string
  description = "Deployment environment label, used for the four CM-6 labels on labelable resources."
  default     = "dev"
}

# WIF parameters --------------------------------------------------------

variable "github_org_repo" {
  type        = string
  description = "OWNER/REPO literal pinning the WIF attribute_condition. Spelling, case, and the slash all matter — this is the entire reason the impersonation surface is one repo, not the public internet. The lab walkthrough uses GRCEngClub/cgep-app-starter."
  default     = "GRCEngClub/cgep-app-starter"
}

variable "wif_pool_id" {
  type        = string
  description = "WIF pool ID. Combined with provider_id and project_number to form the resource name referenced in google-github-actions/auth's workload_identity_provider input."
  default     = "github-actions"
}

variable "wif_provider_id" {
  type        = string
  description = "WIF provider ID within the pool. The provider authenticates GitHub Actions' OIDC tokens (issuer = https://token.actions.githubusercontent.com)."
  default     = "github"
}

variable "service_account_id" {
  type        = string
  description = "Service account ID (the part before @<project>.iam.gserviceaccount.com). The SA that GitHub Actions impersonates via WIF. Given the iam.disableServiceAccountKeyCreation Org Policy, this SA can NEVER have a long-lived key — only WIF or a metadata-server-attached workload can use it."
  default     = "cgep-grc-gate-sa"
}
