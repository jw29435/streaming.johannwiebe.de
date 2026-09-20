# Die VM holt ihre Konfiguration beim Booten aus diesem Bucket. Damit ist eine
# Änderung an vm/ ein "tofu apply" plus ein Neustart des Dienstes — kein Bearbeiten
# von Dateien auf der Maschine.

resource "google_storage_bucket" "config" {
  name                        = local.config_bucket
  location                    = var.region
  storage_class               = "STANDARD"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true

  versioning {
    enabled = true
  }

  depends_on = [google_project_service.required]
}

locals {
  config_objects = {
    "docker-compose.yml" = templatefile("${path.module}/../vm/docker-compose.yml.tftpl", {
      ome_image   = var.ome_image
      caddy_image = var.caddy_image
    })

    "ome/Server.xml" = templatefile("${path.module}/../vm/ome/Server.xml.tftpl", {
      channels             = var.ingest_channels
      quality_profile      = var.quality_profile
      hls_event_playlist   = var.hls_event_playlist
      hls_dvr_max_duration = var.hls_dvr_max_duration
      hls_segment_duration = var.hls_segment_duration
      hls_segment_count    = var.hls_segment_count
      ome_access_token     = random_password.ome_access_token.result
    })

    "ome/Logger.xml"  = file("${path.module}/../vm/ome/Logger.xml")
    "caddy/Caddyfile" = file("${path.module}/../vm/caddy/Caddyfile")

    "scripts/refresh.sh" = templatefile("${path.module}/../vm/scripts/refresh.sh.tftpl", {
      project_id         = var.project_id
      config_bucket      = local.config_bucket
      ip_type            = var.ip_type
      cloudflare_zone_id = var.cloudflare_zone_id
      origin_host        = local.origin_host
      ingest_host        = local.ingest_host
      site_origin        = local.site_origin
      channels           = var.ingest_channels
    })

    "scripts/conclude.sh" = templatefile("${path.module}/../vm/scripts/conclude.sh.tftpl", {
      project_id = var.project_id
      channels   = var.ingest_channels
    })

    "scripts/cpu-watch.sh" = file("${path.module}/../vm/scripts/cpu-watch.sh")
  }

  # Ändert sich irgendeine Konfigurationsdatei, ändert sich dieser Wert. Er steht in
  # den VM-Metadaten, damit man auf der Maschine nachsehen kann, welcher Stand läuft.
  #
  # nonsensitive, weil in Server.xml das OME-Access-Token steckt und die Prüfsumme
  # sonst als geheim gälte. Aus einer MD5-Summe lässt sich das Token nicht zurückholen,
  # und als geheim markierte Metadaten würden jede Planausgabe unlesbar machen.
  config_hash = nonsensitive(md5(join("", [for k in sort(keys(local.config_objects)) : md5(local.config_objects[k])])))
}

resource "google_storage_bucket_object" "config" {
  for_each = local.config_objects

  bucket  = google_storage_bucket.config.name
  name    = each.key
  content = each.value

  # Ohne das würde Google den Inhalt raten; die Skripte sollen als Text ankommen.
  content_type = endswith(each.key, ".xml") ? "application/xml" : "text/plain"
}
