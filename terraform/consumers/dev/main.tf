# consumers/dev/main.tf
terraform {
  required_version = ">= 1.6"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
    random = { source = "hashicorp/random", version = "~> 3.6" }
  }
}

provider "google" {
  project = "project-a383fc9e-52f5-406a-9e8"
  region  = "us-central1"
}

# Stable per-workspace random suffix. Terraform stores the value in state,
# so the same suffix is used on every apply — bucket name is consistent.
resource "random_id" "bucket_suffix" {
  byte_length = 4  # 8 hex characters, e.g. "3a7f9b2c"
}

module "data_bucket" {
  source = "../../modules/compliant-gcs-bucket"

  gcp_project        = "project-a383fc9e-52f5-406a-9e8"
  project_label      = "cgep-lab"
  environment        = "dev"
  retention_days     = 30
  bucket_name_suffix = "data-${random_id.bucket_suffix.hex}"
}

output "attestation" { value = module.data_bucket.compliance_attestation }
output "bucket_url"  { value = module.data_bucket.bucket_url }
