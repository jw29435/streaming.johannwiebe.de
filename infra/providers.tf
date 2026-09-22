terraform {
  required_version = ">= 1.8"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.3"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.25"
    }
    bunnynet = {
      source  = "BunnyWay/bunnynet"
      version = "~> 0.18"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region

  # Die Firebase-APIs — hier firebaserules — verlangen ein Kontingentprojekt im
  # Kopf jeder Anfrage. Ohne das schlagen sie mit 403 "requires a quota project"
  # fehl, je nachdem wie die Anmeldedaten auf dem Rechner eingerichtet sind.
  # Belastet wird dasselbe Projekt, in dem auch alles andere liegt.
  user_project_override = true
  billing_project       = var.project_id
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "bunnynet" {
  api_key = var.bunny_api_key
}
