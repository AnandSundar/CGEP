# policies/tests/au2_data_access_logs_gcp_test.rego
# Lab 5.4 — Rego tests for the AU-2 Data Access audit logs gate.
package compliance.au2_gcp_test

import rego.v1
import data.compliance.au2_gcp

# --- Compliant: all three services, all three log types --------------

compliant_input := {"configuration": {"root_module": {"resources": [
	{
		"address": "google_project_iam_audit_config.storage",
		"type": "google_project_iam_audit_config",
		"values": {
			"service": "storage.googleapis.com",
			"audit_log_config": [
				{"log_type": {"constant_value": "DATA_READ"}},
				{"log_type": {"constant_value": "DATA_WRITE"}},
				{"log_type": {"constant_value": "ADMIN_READ"}},
			],
		},
	},
	{
		"address": "google_project_iam_audit_config.kms",
		"type": "google_project_iam_audit_config",
		"values": {
			"service": "cloudkms.googleapis.com",
			"audit_log_config": [
				{"log_type": {"constant_value": "DATA_READ"}},
				{"log_type": {"constant_value": "DATA_WRITE"}},
				{"log_type": {"constant_value": "ADMIN_READ"}},
			],
		},
	},
	{
		"address": "google_project_iam_audit_config.iam",
		"type": "google_project_iam_audit_config",
		"values": {
			"service": "iam.googleapis.com",
			"audit_log_config": [
				{"log_type": {"constant_value": "DATA_READ"}},
				{"log_type": {"constant_value": "DATA_WRITE"}},
				{"log_type": {"constant_value": "ADMIN_READ"}},
			],
		},
	},
]}}}

# --- Noncompliant: storage and kms present, iam MISSING --------------

missing_service_input := {"configuration": {"root_module": {"resources": [
	{
		"address": "google_project_iam_audit_config.storage",
		"type": "google_project_iam_audit_config",
		"values": {
			"service": "storage.googleapis.com",
			"audit_log_config": [
				{"log_type": {"constant_value": "DATA_READ"}},
				{"log_type": {"constant_value": "DATA_WRITE"}},
				{"log_type": {"constant_value": "ADMIN_READ"}},
			],
		},
	},
	{
		"address": "google_project_iam_audit_config.kms",
		"type": "google_project_iam_audit_config",
		"values": {
			"service": "cloudkms.googleapis.com",
			"audit_log_config": [
				{"log_type": {"constant_value": "DATA_READ"}},
				{"log_type": {"constant_value": "DATA_WRITE"}},
				{"log_type": {"constant_value": "ADMIN_READ"}},
			],
		},
	},
	# google_project_iam_audit_config.iam is intentionally absent
]}}}

# --- Noncompliant: storage present but only DATA_READ enabled --------
# This is the "silent regression" the gate exists to catch —
# someone reduced the audit_log_config block and didn't notice.

partial_input := {"configuration": {"root_module": {"resources": [
	{
		"address": "google_project_iam_audit_config.storage",
		"type": "google_project_iam_audit_config",
		"values": {
			"service": "storage.googleapis.com",
			"audit_log_config": [
				{"log_type": {"constant_value": "DATA_READ"}},
			],
		},
	},
	{
		"address": "google_project_iam_audit_config.kms",
		"type": "google_project_iam_audit_config",
		"values": {
			"service": "cloudkms.googleapis.com",
			"audit_log_config": [
				{"log_type": {"constant_value": "DATA_READ"}},
				{"log_type": {"constant_value": "DATA_WRITE"}},
				{"log_type": {"constant_value": "ADMIN_READ"}},
			],
		},
	},
	{
		"address": "google_project_iam_audit_config.iam",
		"type": "google_project_iam_audit_config",
		"values": {
			"service": "iam.googleapis.com",
			"audit_log_config": [
				{"log_type": {"constant_value": "DATA_READ"}},
				{"log_type": {"constant_value": "DATA_WRITE"}},
				{"log_type": {"constant_value": "ADMIN_READ"}},
			],
		},
	},
]}}}

# --- Noncompliant: NO audit configs at all ---------------------------

empty_input := {"configuration": {"root_module": {"resources": []}}}

# --- Tests ------------------------------------------------------------

test_compliant_passes if {
	count(au2_gcp.deny) == 0 with input as compliant_input
}

test_missing_service_fails if {
	some msg in au2_gcp.deny with input as missing_service_input
	contains(msg, "AU-2")
	contains(msg, "iam.googleapis.com")
}

test_partial_log_types_fails if {
	some msg in au2_gcp.deny with input as partial_input
	contains(msg, "AU-2")
	contains(msg, "storage.googleapis.com")
	# Should name the missing log types in the message
	contains(msg, "DATA_WRITE")
	contains(msg, "ADMIN_READ")
}

test_empty_input_fails if {
	count(au2_gcp.deny) == 3 with input as empty_input
}