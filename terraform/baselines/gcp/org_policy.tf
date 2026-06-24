# terraform/baselines/gcp/org_policy.tf
# Lab 5.4 — Org Policy at project scope (CM-6, AC-2, AC-3)
#
# Each `google_org_policy_policy` sets `enforce = "TRUE"`, which
# means non-compliant API calls are REJECTED — not flagged, not
# audited after the fact, REJECTED at the moment of the call. That's
# defense-in-depth's strongest layer. The "audit only" mode is
# `inherit` (omit the rules block) — the policy is then visible in
# the listing but doesn't block anything.
#
# All three policies are project-scoped. To target the org or a
# folder, swap the `parent` value (and the `name` prefix). The
# constraint names stay the same.

# CM-6: every new GCS bucket must use uniform bucket-level access.
# Without this, an operator can create a bucket whose IAM includes
# allUsers — a "soft" public bucket that the SC-28 / AC-3 Rego
# policies catch after the fact but the org policy prevents
# preemptively. Pairs with the GCS public_access_prevention
# enforcement in policies/ac3_no_public.rego.
resource "google_org_policy_policy" "uniform_bucket_access" {
  name   = "projects/${var.gcp_project}/policies/storage.uniformBucketLevelAccess"
  parent = "projects/${var.gcp_project}"

  spec {
    rules { enforce = "TRUE" }
  }
}

# AC-2: disables long-lived service account key creation. This is
# the policy that rejects the lab walkthrough's intentional
# "gcloud iam service-accounts keys create" attempt with
# FAILED_PRECONDITION. After this is in effect, the only way to
# authenticate as a SA is via WIF, a metadata-server-attached
# workload, or impersonation (which itself requires a higher-priv
# principal that already has access).
resource "google_org_policy_policy" "disable_sa_keys" {
  name   = "projects/${var.gcp_project}/policies/iam.disableServiceAccountKeyCreation"
  parent = "projects/${var.gcp_project}"

  spec {
    rules { enforce = "TRUE" }
  }
}

# AC-3: forces every new Compute Engine instance to require OS
# Login. SSH keys then live in project IAM, not on the instance
# metadata — revoking a user's access is one IAM change, not a
# hunt across every VM's sshd config.
resource "google_org_policy_policy" "require_oslogin" {
  name   = "projects/${var.gcp_project}/policies/compute.requireOsLogin"
  parent = "projects/${var.gcp_project}"

  spec {
    rules { enforce = "TRUE" }
  }
}
