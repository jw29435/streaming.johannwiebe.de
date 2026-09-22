resource "bunnynet_pullzone" "live" {
  name = var.bunny_pullzone_name

  origin {
    type        = "OriginUrl"
    url         = "https://${local.origin_host}"
    host_header = local.origin_host
    verify_ssl  = true
    # Caddy leitet nicht um; eine Umleitung wäre ein Fehler und soll auffallen.
    follow_redirects = false
  }

  routing {
    # Standard-Netz mit 119 Standorten. Das Volume-Netz halbiert den Preis,
    # hat aber nur 10 Standorte — ein Versuch wert, wenn der Traffic wächst.
    tier = "Standard"
  }

  # Origin Shield: Alle Knoten holen über einen Zwischenspeicher ab, damit die VM
  # jedes Segment nur einmal ausliefert. In Europa gibt es nur FR.
  originshield_enabled = true
  originshield_zone    = "FR"

  # Zusammengefasste Anfragen: Fragen hundert Knoten gleichzeitig nach demselben
  # frischen Segment, geht trotzdem nur eine Anfrage an die VM.
  request_coalescing_enabled = true
  request_coalescing_timeout = 10

  # -1 heißt "Cache-Control des Origin beachten". Damit gelten die Werte aus dem
  # Caddyfile: Playlists 2 Sekunden, Segmente 1 Stunde.
  cache_enabled                 = true
  cache_expiration_time         = -1
  cache_expiration_time_browser = -1
  cache_errors                  = false

  # HLS mit TS läuft auch über "…/master.m3u8?format=ts". Ohne diesen Eintrag
  # würde Bunny den Query-String ignorieren und beide Varianten verwechseln.
  cache_vary_querystring = ["format"]

  # Caddy spiegelt die anfragende Herkunft in Access-Control-Allow-Origin zurück.
  # Ohne diese Zeile würde Bunny die Antwort für eine Herkunft allen anderen
  # vorsetzen, und der Browser bräche mit einem CORS-Fehler ab.
  cache_vary_headers = ["Origin"]

  strip_cookies = true

  # CORS setzt Caddy mit der konkreten Herkunft. Bunnys eigene CORS-Funktion würde
  # daraus ein "*" machen — deshalb bleibt sie aus.
  cors_enabled = false
}

# Der geheime Header zum Origin. Die Pull Zone hat dafür kein eigenes Feld,
# also läuft er als Edge Rule über alle Anfragen.
resource "bunnynet_pullzone_edgerule" "origin_auth" {
  pullzone    = bunnynet_pullzone.live.id
  enabled     = true
  description = "Geheimer Header, ohne den Caddy mit 403 antwortet"
  match_type  = "MatchAny"

  actions = [
    {
      type       = "SetRequestHeader"
      parameter1 = "X-Origin-Auth"
      parameter2 = random_password.origin_auth.result
      parameter3 = null
    }
  ]

  triggers = [
    {
      type       = "Url"
      match_type = "MatchAny"
      patterns   = ["*"]
      parameter1 = null
      parameter2 = null
    }
  ]
}

# Ohne "certificate" stellt Bunny selbst ein Let's-Encrypt-Zertifikat aus.
# Das geht erst, wenn der CNAME steht — daher das depends_on.
resource "bunnynet_pullzone_hostname" "live" {
  pullzone    = bunnynet_pullzone.live.id
  name        = local.live_host
  tls_enabled = true
  force_ssl   = true

  depends_on = [cloudflare_dns_record.live]
}
