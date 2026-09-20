# Alle Einträge stehen auf "DNS only" (proxied = false). Über den Cloudflare-Proxy
# käme weder SRT noch das Zertifikat von Bunny sauber durch.

# Bei fester IP schreibt Terraform die A-Einträge. Bei wechselnder IP fehlen sie hier
# mit Absicht: Dann trägt die VM sie beim Booten selbst ein (vm/scripts/refresh.sh),
# und Terraform würde ihr sonst bei jedem Lauf dazwischenfunken.
resource "cloudflare_dns_record" "origin" {
  count = var.ip_type == "static" ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = local.origin_host
  type    = "A"
  content = google_compute_address.media[0].address
  ttl     = 60
  proxied = false
  comment = "Media-VM, nur Bunny holt hier ab (Terraform)"
}

resource "cloudflare_dns_record" "ingest" {
  count = var.ip_type == "static" ? 1 : 0

  zone_id = var.cloudflare_zone_id
  name    = local.ingest_host
  type    = "A"
  content = google_compute_address.media[0].address
  ttl     = 60
  proxied = false
  comment = "Ziel für OBS, SRT und RTMP (Terraform)"
}

# Der CNAME auf die Pull Zone muss stehen, bevor Bunny sein Zertifikat ausstellen kann.
# Deshalb hängt bunnynet_pullzone_hostname.live an diesem Eintrag.
resource "cloudflare_dns_record" "live" {
  zone_id = var.cloudflare_zone_id
  name    = local.live_host
  type    = "CNAME"
  content = "${var.bunny_pullzone_name}.b-cdn.net"
  ttl     = 300
  proxied = false
  comment = "Video für Zuschauer über Bunny CDN (Terraform)"
}
