# terraform/main.tf
# AWS compliance baseline (Lab 2.3) wired into the Lab 4.3 evidence pipeline.
# The grc-gate workflow plans this on every PR; Conftest + tfsec evaluate plan.json.
#
# CM-3 (configuration change control): every resource declared here.
# CM-6 (configuration settings):       default_tags below enforce the four required tags.
# SC-28 (protection of information at rest): composed via primitives/compliant-s3.
# AC-3  (access enforcement):           public access block in the primitive.
# AU-3 / AU-6 / AU-9 (audit):           server access logs in the primitive; vault in Lab 2.5.

terraform {
  required_version = ">= 1.6"
  required_providers {
    aws    = { source = "hashicorp/aws",    version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "aws" {
  region = "us-east-1"

  # CM-6: default_tags enforce the four required tags on every taggable
  # resource. Removes the chance of forgetting them on a new resource block.
  default_tags {
    tags = {
      Project         = var.project_name
      Environment     = var.environment
      ManagedBy       = "terraform"
      ComplianceScope = "cge-p-lab"
    }
  }
}

variable "project_name" {
  type        = string
  description = "Short project identifier used in bucket names and the Project tag."
  default     = "cgep"
}

variable "environment" {
  type        = string
  description = "Deployment environment (dev, staging, prod). Drives the Environment tag."
  default     = "dev"
}

# Compose the Lab 2.3 compliant-s3 primitive. SC-28 (encryption + versioning),
# AC-3 (public access block), CM-6 (tagging via default_tags), AU-3/AU-6 (logs).
module "data_bucket" {
  source = "./primitives/compliant-s3"

  project_name = var.project_name
  environment  = var.environment
}

# Compose the Lab 2.5 evidence vault so the OIDC plan also exercises
# object-lock / retention / deny-delete controls.
module "evidence_vault" {
  source = "./primitives/evidence-vault"

  project_name   = var.project_name
  lock_mode      = "GOVERNANCE"
  retention_days = 90
}

output "data_bucket_name" { value = module.data_bucket.bucket_name }
output "data_bucket_arn"  { value = module.data_bucket.bucket_arn }
output "data_encryption"  { value = module.data_bucket.encryption_algorithm }
output "vault_name"       { value = module.evidence_vault.vault_name }
