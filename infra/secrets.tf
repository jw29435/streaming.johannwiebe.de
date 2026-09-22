# Stream-Keys, X-Origin-Auth und das OME-Access-Token erzeugt Terraform selbst.
# 32 Zeichen, nur Buchstaben und Ziffern — Sonderzeichen würden in der SRT-streamid
# und in HTTP-Headern nur Ärger machen.

resource "random_password" "stream_key" {
  for_each = local.channels

  length  = 32
  special = false
}

resource "random_password" "origin_auth" {
  length  = 32
  special = false
}

resource "random_password" "ome_access_token" {
  length  = 32
  special = false
}

# ---------------------------------------------------------------------------
# Secret Manager
# ---------------------------------------------------------------------------

resource "google_secret_manager_secret" "generated" {
  for_each = local.generated_secrets

  secret_id = each.key

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "generated" {
  for_each = local.generated_secrets

  secret      = google_secret_manager_secret.generated[each.key].id
  secret_data = each.value
}

# Der Cloudflare-Token wird nicht erzeugt, sondern in der Cloudflare-Oberfläche
# ausgestellt. Terraform legt nur die Hülle an; die VM liest ihn beim Booten,
# um ihre wechselnde IP einzutragen.
resource "google_secret_manager_secret" "cloudflare_dns_token" {
  secret_id = "cloudflare-dns-token"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

resource "google_secret_manager_secret_version" "cloudflare_dns_token" {
  secret      = google_secret_manager_secret.cloudflare_dns_token.id
  secret_data = var.cloudflare_api_token
}
