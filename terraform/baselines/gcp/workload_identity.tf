# terraform/baselines/gcp/workload_identity.tf
# Lab 5.4 — Workload Identity Federation for GitHub Actions
#
# Pool, provider, service account, IAM binding. Together they let
# a GitHub Actions job authenticate to GCP using a short-lived OIDC
# token instead of a long-lived service account JSON key. The
# attribute_condition is the single most important line — without
# it, ANY GitHub repo on the public internet could impersonate
# this SA.

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = var.wif_pool_id
  display_name              = "GitHub Actions (${var.project_name})"
  description               = "Pool for GitHub Actions OIDC tokens (Lab 5.4). All token exchange happens here; no service account keys are involved."
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = var.wif_provider_id
  display_name                       = "GitHub (${var.project_name})"

  # Map the GitHub OIDC claims onto GCP's federated identity
  # attributes. `attribute.repository` is what the IAM binding
  # below references via principalSet; if you rename it here,
  # update the principalSet too.
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.actor"      = "assertion.actor"
  }

  # Pin to ONE repo. assertion.repository is the OWNER/REPO literal
  # GitHub issues; spelling, case, and the slash all matter. To
  # allow a different repo, change this string. To allow ALL public
  # repos, remove the condition — not recommended. To pin to a
  # specific branch, switch to a principal:// binding and add
  # `assertion.ref == "refs/heads/main"` to the condition.
  attribute_condition = "assertion.repository == \"${var.github_org_repo}\""

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# The SA that GitHub Actions impersonates. With the
# iam.disableServiceAccountKeyCreation Org Policy in effect, this
# account is unreachable via JSON keys — it can only be used via
# WIF, attached to a workload (GCE/GKE/Cloud Run), or impersonated
# by a higher-priv principal.
resource "google_service_account" "gha" {
  account_id   = var.service_account_id
  display_name = "CGE-P GRC gate (read-only)"
  description  = "SA impersonated by GitHub Actions via WIF. Has roles/viewer. No JSON keys (Org Policy forbids them)."
}

# roles/viewer is the least-privilege baseline for the demo
# workflow in .github/workflows/gcp-wif-demo.yml. Tighten by
# replacing with the specific role your capstone actually needs —
# e.g. roles/storage.objectViewer for bucket-only reads.
resource "google_project_iam_member" "gha_viewer" {
  project = var.gcp_project
  role    = "roles/viewer"
  member  = "serviceAccount:${google_service_account.gha.email}"
}

# principalSet with attribute.repository matches the
# attribute_condition above. principalSet: ALL GitHub workflow
# runs from this one repo. To pin to a specific branch or
# workflow file, add a second condition on `assertion.ref` or
# switch the principal to a `principal://.../attribute.<key>/<value>`
# exact-match form.
resource "google_service_account_iam_binding" "wif_user" {
  service_account_id = google_service_account.gha.name
  role               = "roles/iam.workloadIdentityUser"

  members = [
    "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org_repo}",
  ]
}
