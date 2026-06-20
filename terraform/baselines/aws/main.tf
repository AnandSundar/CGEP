# terraform/baselines/aws/main.tf
# Lab 5.2 — AWS Security Services Baseline
#
# Multi-region CloudTrail (AU-2/AU-12/AU-10) plus Security Hub
# (RA-5/SI-4) aggregation. AWS Config is intentionally NOT included
# because an org-level SCP denies config:* to non-management accounts;
# the absence is documented via the Security Hub Config.1 control
# finding captured as evidence.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws",    version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = var.aws_region

  # CM-6: default_tags propagate the four required tags to every
  # taggable resource (incl. aws_cloudtrail — checked by
  # policies/cm6_required_tags_aws.rego).
  default_tags {
    tags = {
      Project         = var.project_name
      Environment     = var.environment
      ManagedBy       = "terraform"
      ComplianceScope = "cge-p-lab"
    }
  }
}
