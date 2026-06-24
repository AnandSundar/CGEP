# terraform/baselines/gcp/audit_logs.tf
# Lab 5.4 — Data Access audit logs (AU-2)
#
# Data Access logs are OFF BY DEFAULT in GCP. This is the #1
# audit finding on GCP environments because nobody turns them on.
# Each `google_project_iam_audit_config` enables the three log
# types for one service:
#   - DATA_READ   — every read of user data
#   - DATA_WRITE  — every write of user data
#   - ADMIN_READ  — every read of metadata/config (the most
#                   useful one for change-tracking)
#
# The IAM policy JSON (output of `gcloud projects get-iam-policy`)
# captures this as the `auditConfigs` block. Conftest checks that
# the three services required by this lab each have all three log
# types — see policies/au2_data_access_logs_gcp.rego.

resource "google_project_iam_audit_config" "storage" {
  project = var.gcp_project
  service = "storage.googleapis.com"

  audit_log_config { log_type = "DATA_READ" }
  audit_log_config { log_type = "DATA_WRITE" }
  audit_log_config { log_type = "ADMIN_READ" }
}

resource "google_project_iam_audit_config" "kms" {
  project = var.gcp_project
  service = "cloudkms.googleapis.com"

  audit_log_config { log_type = "DATA_READ" }
  audit_log_config { log_type = "DATA_WRITE" }
  audit_log_config { log_type = "ADMIN_READ" }
}

resource "google_project_iam_audit_config" "iam" {
  project = var.gcp_project
  service = "iam.googleapis.com"

  audit_log_config { log_type = "ADMIN_READ" }
  audit_log_config { log_type = "DATA_READ" }
  audit_log_config { log_type = "DATA_WRITE" }
}
