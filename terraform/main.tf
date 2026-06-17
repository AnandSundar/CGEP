# terraform/main.tf
# Clean compliance baseline: every resource satisfies SC-28, AC-3, and CM-6.
# Run `opa eval` against terraform/plan.json — every deny set should be empty.

terraform {
  required_version = ">= 1.6"
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

provider "google" {
  project = var.gcp_project
  region  = "us-central1"
}

variable "gcp_project" { type = string }

# --- KMS for CMEK ------------------------------------------------------
resource "google_kms_key_ring" "ring" {
  name     = "lab33-ring"
  location = "us-central1"
}

resource "google_kms_crypto_key" "key" {
  name     = "lab33-key"
  key_ring = google_kms_key_ring.ring.id
}

# --- Network ----------------------------------------------------------
resource "google_compute_network" "demo" {
  name                    = "lab33-demo"
  auto_create_subnetworks = false
}

# --- Firewall: HTTPS from internal range only (no public mgmt ports) -
resource "google_compute_firewall" "internal_https" {
  name          = "lab33-internal-https"
  network       = google_compute_network.demo.name
  direction     = "INGRESS"
  source_ranges = ["10.0.0.0/8"]
  allow {
    protocol = "tcp"
    ports    = ["443"]
  }
}

# --- Compliant GCS bucket: CMEK, locked down, all four labels --------
resource "google_storage_bucket" "good" {
  name                        = "${var.gcp_project}-lab33-good"
  location                    = "us-central1"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  encryption { default_kms_key_name = google_kms_crypto_key.key.id }

  labels = {
    project          = "lab33"
    environment      = "dev"
    managed_by       = "terraform"
    compliance_scope = "cge-p-lab"
  }
}

# --- Compliant compute instance: all four labels ---------------------
resource "google_compute_instance" "compliant_vm" {
  name         = "lab33-compliant-vm"
  machine_type = "e2-medium"
  zone         = "us-central1-a"

  boot_disk {
    initialize_params { image = "debian-cloud/debian-12" }
  }

  network_interface {
    network = google_compute_network.demo.name
  }

  labels = {
    project          = "lab33"
    environment      = "dev"
    managed_by       = "terraform"
    compliance_scope = "cge-p-lab"
  }
}

# --- Compliant compute disk: all four labels -------------------------
resource "google_compute_disk" "compliant_disk" {
  name = "lab33-compliant-disk"
  zone = "us-central1-a"
  type = "pd-standard"
  size = 10

  labels = {
    project          = "lab33"
    environment      = "dev"
    managed_by       = "terraform"
    compliance_scope = "cge-p-lab"
  }
}
