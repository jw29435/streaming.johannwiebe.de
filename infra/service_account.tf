resource "google_service_account" "media_vm" {
  account_id   = "media-vm"
  display_name = "Media-VM (OvenMediaEngine, Caddy)"
  description  = "Dienstkonto der Media-VM. Darf Secrets lesen, die Konfiguration holen und loggen — sonst nichts."
}

# Lesen darf die VM nur genau die Secrets, die sie braucht, nicht alle im Projekt.
resource "google_secret_manager_secret_iam_member" "vm_reads_generated" {
  for_each = google_secret_manager_secret.generated

  secret_id = each.value.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.media_vm.email}"
}

resource "google_secret_manager_secret_iam_member" "vm_reads_cloudflare_token" {
  secret_id = google_secret_manager_secret.cloudflare_dns_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.media_vm.email}"
}

# Nur lesen, und nur in diesem einen Bucket.
resource "google_storage_bucket_iam_member" "vm_reads_config" {
  bucket = google_storage_bucket.config.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.media_vm.email}"
}

resource "google_project_iam_member" "vm_writes_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.media_vm.email}"
}
