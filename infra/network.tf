# Ein eigenes Netz statt des Standardnetzes: Das Standardnetz bringt eine Regel mit,
# die SSH aus dem ganzen Internet erlaubt. Genau das soll hier nicht sein.

resource "google_compute_network" "media" {
  name                    = "media-net"
  auto_create_subnetworks = false

  depends_on = [google_project_service.required]
}

resource "google_compute_subnetwork" "media" {
  name          = "media-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.media.id
}

# OBS sendet hierhin: SRT über UDP, RTMP als Rückfallebene.
resource "google_compute_firewall" "ingest" {
  name        = "media-allow-ingest"
  network     = google_compute_network.media.name
  description = "SRT und RTMP von OBS"

  allow {
    protocol = "udp"
    ports    = ["9999"]
  }

  allow {
    protocol = "tcp"
    ports    = ["1935"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["media-vm"]
}

# Port 80 bleibt offen, weil Caddy darüber sein Let's-Encrypt-Zertifikat holt.
# Über 443 holt ausschließlich Bunny ab; wer den geheimen Header nicht mitschickt,
# bekommt von Caddy eine 403.
resource "google_compute_firewall" "web" {
  name        = "media-allow-web"
  network     = google_compute_network.media.name
  description = "HTTPS für Bunny, HTTP für die Zertifikatsprüfung"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["media-vm"]
}

# SSH nur aus dem IAP-Bereich von Google. Eine öffentliche SSH-Regel gibt es nicht,
# Zugang läuft ausschließlich über "gcloud compute ssh --tunnel-through-iap".
resource "google_compute_firewall" "ssh_iap" {
  name        = "media-allow-ssh-iap"
  network     = google_compute_network.media.name
  description = "SSH ausschließlich über Identity-Aware Proxy"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]
  target_tags   = ["media-vm"]
}

# Der HLS-Port 13333 bekommt bewusst keine Regel: Caddy erreicht ihn über
# 127.0.0.1, von außen ist er dicht.
