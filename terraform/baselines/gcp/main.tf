# terraform/baselines/gcp/main.tf
# Lab 5.4 — GCP Security Services Baseline
#
# Three layers, all in one Terraform root:
#   1. Org Policy  (org_policy.tf)            — REJECT at the API for
#      non-compliant resource creation. CM-6, AC-2, AC-3.
#   2. Workload Identity Federation
#      (workload_identity.tf)                — short-lived OIDC tokens
#      in place of long-lived SA JSON keys. AC-2.
#   3. Data Access audit logs (audit_logs.tf) — per-service, off by
#      default in GCP. AU-2.
#
# Provider uses ADC (Application Default Credentials) per the lab
# prereq. Run `gcloud auth application-default login` once on the
# machine that runs `terraform apply`. There are no service account
# JSON keys anywhere in this root — the Org Policy
# `iam.disableServiceAccountKeyCreation = TRUE` would reject the
# creation of one even if you tried.
#
# ADC + orgpolicy.googleapis.com / cloudresourcemanager.googleapis.com
# REQUIRE a quota project. When using user credentials (the result of
# `gcloud auth application-default login`), set:
#
#   export GOOGLE_CLOUD_QUOTA_PROJECT="$GCP_PROJECT"
#
# before `terraform apply`. Without it, Org Policy and audit-config
# resources fail with 403 "SERVICE_DISABLED" and consumer set to a
# different project than your target.

terraform {
  required_version = ">= 1.6"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
}
