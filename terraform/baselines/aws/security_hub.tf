# terraform/baselines/aws/security_hub.tf
# Lab 5.2 — Security Hub
#
# RA-5 (vulnerability monitoring): aggregated findings across controls.
# SI-4 (system monitoring):       continuous control evaluation.
#
# aws_securityhub_account.this  — IMPORTED (pre-existing in this account).
# aws_securityhub_standards_subscription.fsbp — IMPORTED (pre-existing).
# aws_securityhub_standards_subscription.nist_800_53 — NEW.

# enable_default_standards is pinned to false to match the pre-existing
# state (set when the account first enabled Hub in 2026-04-02). The
# resource default is true, which would force a destroy-recreate on
# first apply and briefly take Hub offline. We want to manage the
# existing Hub, not replace it.
resource "aws_securityhub_account" "this" {
  enable_default_standards = false
}

resource "aws_securityhub_standards_subscription" "fsbp" {
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/aws-foundational-security-best-practices/v/1.0.0"
  depends_on    = [aws_securityhub_account.this]
}

resource "aws_securityhub_standards_subscription" "nist_800_53" {
  standards_arn = "arn:aws:securityhub:${var.aws_region}::standards/nist-800-53/v/5.0.0"
  depends_on    = [aws_securityhub_account.this]
}
