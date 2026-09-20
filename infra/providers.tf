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
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "bunnynet" {
  api_key = var.bunny_api_key
}
