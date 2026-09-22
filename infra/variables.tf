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
  description = <<-EOT
    Segmentlänge in Sekunden — der wirksamste Hebel gegen die Verzögerung.

    Player halten sich nach HLS-Spezifikation drei Segmentlängen vom Live-Punkt fern.
    Mit 4 s sind allein das 12 s; gemessen wurden damit 23 s insgesamt, bei nur 0,9 s
    Rückstand auf der VM. Die Verzögerung entsteht also fast vollständig im Player.

    2 s halbiert den Rückhalt. Voraussetzung ist, dass OBS alle 2 s ein Schlüsselbild
    sendet, sonst schneiden die Segmente nicht sauber. Apple empfiehlt 6 s und die
    OME-Doku warnt vor sehr kurzen Werten bei älteren Playern — deshalb nicht unter 2.
  EOT
  type        = number
  default     = 2
}

variable "hls_segment_count" {
  description = <<-EOT
    Segmente in der Playlist. Nie unter 3, das verlangt die Spezifikation.
    Gegen die Verzögerung hilft hls_segment_duration deutlich mehr als dieser Wert.
  EOT
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

variable "site_origins" {
  description = <<-EOT
    Herkünfte, denen Caddy den Abruf per JavaScript erlaubt. Caddy spiegelt die
    passende zurück, alles andere bekommt gar keine CORS-Kopfzeile.

    Die web.app-Adresse gehört dazu, weil Firebase Hosting immer darüber erreichbar ist —
    auch nachdem die eigene Domain eingerichtet ist. Ohne sie schlägt jeder Test fehl,
    der nicht über die endgültige Adresse läuft.
  EOT
  type        = list(string)
  default = [
    "https://streaming.johannwiebe.de",
    "https://stream-johannwiebe-de.web.app",
  ]
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
