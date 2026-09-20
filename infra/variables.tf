# ---------------------------------------------------------------------------
# Google Cloud
# ---------------------------------------------------------------------------

variable "project_id" {
  description = "GCP-Projekt, in dem alles liegt."
  type        = string
  default     = "stream-johannwiebe-de"
}

variable "region" {
  description = "Region der VM und des Konfig-Buckets."
  type        = string
  default     = "europe-west3"
}

variable "zone" {
  description = "Zone der VM."
  type        = string
  default     = "europe-west3-c"
}

# ---------------------------------------------------------------------------
# Ausbaustufe — das sind die Stellschrauben aus dem Konzept
# ---------------------------------------------------------------------------

variable "machine_type" {
  description = "Maschinentyp der Media-VM. Startprofil e2-standard-4, Normalprofil c3-standard-8."
  type        = string
  default     = "e2-standard-4"
}

variable "disk_size_gb" {
  description = <<-EOT
    Größe der Boot-Disk in GB. Hier liegen auch die DVR-Segmente.
    Gerechnet für zwei Streams à 4 Stunden über alle Stufen (~15 GB) plus System und Reserve.
    Beim gleitenden 10-Minuten-Fenster reichen 20 GB.
  EOT
  type        = number
  default     = 50
}

variable "ip_type" {
  description = <<-EOT
    "ephemeral": Die VM trägt ihre wechselnde IP beim Booten selbst per Cloudflare-API
    in origin und ingest ein (Startprofil, spart ca. 7 $ im Monat).
    "static": feste IP, die Terraform reserviert und in die DNS-Einträge schreibt.
  EOT
  type        = string
  default     = "ephemeral"

  validation {
    condition     = contains(["ephemeral", "static"], var.ip_type)
    error_message = "ip_type muss \"ephemeral\" oder \"static\" sein."
  }
}

variable "quality_profile" {
  description = <<-EOT
    "start": 720p unverändert durchgereicht, 360p und 144p neu kodiert.
    "normal": zusätzlich 480p.
  EOT
  type        = string
  default     = "start"

  validation {
    condition     = contains(["start", "normal"], var.quality_profile)
    error_message = "quality_profile muss \"start\" oder \"normal\" sein."
  }
}

variable "ingest_channels" {
  description = <<-EOT
    Ein Eintrag je Eingang. "app" ist die OME-Anwendung und steht in der Ingest-Adresse,
    "stream" ist der öffentliche Name im Wiedergabepfad. Weil der Ausgabename fest steht,
    taucht der geheime Stream-Key nicht in der öffentlichen Adresse auf.
  EOT
  type = list(object({
    app    = string
    stream = string
  }))
  default = [
    { app = "live1", stream = "kanal1" },
    { app = "live2", stream = "kanal2" },
  ]
}

# ---------------------------------------------------------------------------
# HLS und Zurückspulen
# ---------------------------------------------------------------------------

variable "hls_event_playlist" {
  description = <<-EOT
    true schreibt "#EXT-X-PLAYLIST-TYPE: EVENT" in die Playlist. Nur dann zeigt Safaris
    nativer Player eine Zeitleiste, also gibt es nur dann Zurückspulen im iPhone-Vollbild.
    Dafür wächst die Playlist ab Streamstart und muss vor Ablauf von hls_dvr_max_duration
    mit vm/scripts/conclude.sh beendet werden.

    false ergibt das gleitende Fenster aus dem Konzept: nichts muss beendet werden,
    dafür fehlt die Zeitleiste im iPhone-Vollbild.
  EOT
  type        = bool
  default     = true
}

variable "hls_dvr_max_duration" {
  description = <<-EOT
    Vorgehaltene Zeit zum Zurückspulen, in SEKUNDEN. Die OME-Doku-Tabelle behauptet
    Millisekunden; der Quelltext (hls_stream.cpp: GetMaxDuration() * 1000) belegt Sekunden.
    14400 = 4 Stunden für die EVENT-Playlist, 600 = 10 Minuten für das gleitende Fenster.
  EOT
  type        = number
  default     = 14400
}

variable "hls_segment_duration" {
  description = "Segmentlänge in Sekunden. Kürzer heißt schneller starten, aber unruhiger bei alten Playern."
  type        = number
  default     = 4
}

variable "hls_segment_count" {
  description = "Segmente in der Playlist. Erster Hebel gegen zu hohe Verzögerung: auf 4 senken. Nie unter 3."
  type        = number
  default     = 5
}

# ---------------------------------------------------------------------------
# Fest gepinnte Abbilder — nie "latest", Updates nur an einem Nicht-Streamtag
# ---------------------------------------------------------------------------

variable "ome_image" {
  description = "OvenMediaEngine."
  type        = string
  default     = "airensoft/ovenmediaengine:v0.21.0"
}

variable "caddy_image" {
  description = "Caddy als Origin-Proxy."
  type        = string
  default     = "caddy:2.11.4"
}

# ---------------------------------------------------------------------------
# Namen und DNS
# ---------------------------------------------------------------------------

variable "base_domain" {
  description = "Basis aller Namen dieser Plattform."
  type        = string
  default     = "streaming.johannwiebe.de"
}

variable "cloudflare_zone_id" {
  description = "Zone johannwiebe.de bei Cloudflare."
  type        = string
  default     = "f206f3f9389944adad339c499a659321"
}

variable "bunny_pullzone_name" {
  description = "Name der Bunny Pull Zone. Muss bei Bunny weltweit eindeutig sein."
  type        = string
  default     = "streaming-johannwiebe-de"
}

# ---------------------------------------------------------------------------
# Zugangsdaten — gehören in terraform.tfvars, die .gitignore ausschließt
# ---------------------------------------------------------------------------

variable "cloudflare_api_token" {
  description = "Cloudflare-Token, nur Zone:DNS:Edit für johannwiebe.de."
  type        = string
  sensitive   = true
}

variable "bunny_api_key" {
  description = "API-Schlüssel des Bunny-Kontos."
  type        = string
  sensitive   = true
}
