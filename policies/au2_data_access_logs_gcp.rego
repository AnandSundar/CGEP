# policies/au2_data_access_logs_gcp.rego
# METADATA
# title: AU-2 - Data Access Audit Logs (GCP)
# description: |
#   Every required GCP service must have a
#   google_project_iam_audit_config with DATA_READ, DATA_WRITE,
#   and ADMIN_READ enabled. Data Access logs are off by default in
#   GCP — this gate makes sure a future change can't silently
#   re-disable them. The corresponding evidence is the
#   `auditConfigs` block in `gcloud projects get-iam-policy`,
#   captured as `evidence/lab-5-4/iam-policy.json`.
# custom:
#   control_id: AU-2
#   framework: nist-800-53
#   severity: high
#   remediation: |
#     Add google_project_iam_audit_config resources for
#     storage.googleapis.com, cloudkms.googleapis.com, and
#     iam.googleapis.com, each with DATA_READ, DATA_WRITE, and
#     ADMIN_READ log_type entries.
package compliance.au2_gcp

import rego.v1

# --- Required state --------------------------------------------------

# Lab 5.4 turns on Data Access logs for exactly these three
# services. Adjust if the baseline grows.
required_services := {"storage.googleapis.com", "cloudkms.googleapis.com", "iam.googleapis.com"}

required_log_types := {"DATA_READ", "DATA_WRITE", "ADMIN_READ"}

# --- Rules -----------------------------------------------------------

# Fire when NO google_project_iam_audit_config exists for a
# required service at all. Distinct message so the operator can
# tell "missing entirely" from "present but incomplete".
deny contains msg if {
	some service in required_services
	not has_audit_config(service)
	msg := sprintf(
		"[AU-2] No google_project_iam_audit_config for %q. Data Access logs are off by default in GCP — enable DATA_READ + DATA_WRITE + ADMIN_READ per service.",
		[service],
	)
}

# Fire when an audit config exists for a required service but is
# missing one or more of the three required log types.
deny contains msg if {
	some service in required_services
	some r in input.configuration.root_module.resources
	r.type == "google_project_iam_audit_config"
	r.values.service == service
	present := present_log_types(r)
	missing := required_log_types - present
	count(missing) > 0
	msg := sprintf(
		"[AU-2] google_project_iam_audit_config for %q is missing log types: %v. Data Access logs are off by default — enable all three.",
		[service, concat(",", sort(missing))],
	)
}

# --- Helpers ---------------------------------------------------------

# True iff at least one google_project_iam_audit_config resource
# in the plan targets the given service.
has_audit_config(service) if {
	some r in input.configuration.root_module.resources
	r.type == "google_project_iam_audit_config"
	r.values.service == service
}

# Extract the set of log_type constant values from a single
# audit config resource's `audit_log_config` block.
present_log_types(r) := types if {
	types := {lt |
		some cfg in r.values.audit_log_config
		lt := cfg.log_type.constant_value
	}
}