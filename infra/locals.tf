locals {
  origin_host = "origin.${var.base_domain}"
  ingest_host = "ingest.${var.base_domain}"
  live_host   = "live.${var.base_domain}"

  # Regulärer Ausdruck für Caddys header_regexp. Punkte und Bindestriche werden
  # maskiert, damit aus "stream-johannwiebe-de.web.app" kein Muster wird, auf das
  # auch "streamXjohannwiebeXde" passt.
  site_origin_regex = "^(${join("|", [for o in var.site_origins : replace(o, ".", "\\.")])})$"

  config_bucket = "${var.project_id}-vm-config"

  # Die öffentliche IP der VM: entweder die reservierte oder — bei wechselnder IP —
  # erst nach dem Booten bekannt, dann trägt die VM sie selbst bei Cloudflare ein.
  vm_ip = var.ip_type == "static" ? google_compute_address.media[0].address : google_compute_instance.media.network_interface[0].access_config[0].nat_ip

  # Kanäle nach App-Namen, damit for_each stabile Schlüssel bekommt.
  channels = { for c in var.ingest_channels : c.app => c }

  # Geheimnisse, die Terraform erzeugt und in Secret Manager legt.
  # Der Cloudflare-Token kommt dagegen von Hand aus der Cloudflare-Oberfläche.
  generated_secrets = merge(
    {
      "origin-auth"      = random_password.origin_auth.result
      "ome-access-token" = random_password.ome_access_token.result
    },
    { for app, key in random_password.stream_key : "stream-key-${app}" => key.result }
  )
}
