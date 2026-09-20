output "vm_name" {
  description = "Name der Media-VM, für gcloud-Befehle."
  value       = google_compute_instance.media.name
}

output "vm_zone" {
  description = "Zone der Media-VM."
  value       = google_compute_instance.media.zone
}

output "vm_ip" {
  description = "Öffentliche IP der VM. Bei wechselnder IP gilt sie nur bis zum nächsten Start."
  value       = local.vm_ip
}

output "ssh_command" {
  description = "Einziger Weg auf die Maschine."
  value       = "gcloud compute ssh ${google_compute_instance.media.name} --zone ${var.zone} --project ${var.project_id} --tunnel-through-iap"
}

output "dns_records" {
  description = "Was bei Cloudflare stehen muss. Alles \"DNS only\"."
  value = {
    (local.origin_host) = var.ip_type == "static" ? "A → ${local.vm_ip} (von Terraform gesetzt)" : "A → ${local.vm_ip} (trägt die VM beim Booten selbst ein)"
    (local.ingest_host) = var.ip_type == "static" ? "A → ${local.vm_ip} (von Terraform gesetzt)" : "A → ${local.vm_ip} (trägt die VM beim Booten selbst ein)"
    (local.live_host)   = "CNAME → ${var.bunny_pullzone_name}.b-cdn.net (von Terraform gesetzt)"
    (var.base_domain)   = "A/TXT laut Firebase-Konsole (von Hand)"
  }
}

output "playback_urls" {
  description = "Adressen für die Testseite und zum Prüfen mit curl."
  value = {
    for c in var.ingest_channels :
    c.app => "https://${local.live_host}/${c.app}/${c.stream}/ts:master.m3u8"
  }
}

output "obs_srt_urls" {
  description = "In OBS unter Server eintragen, Stream-Key leer lassen."
  sensitive   = true
  value = {
    for c in var.ingest_channels :
    c.app => "srt://${local.ingest_host}:9999?streamid=default/${c.app}/${random_password.stream_key[c.app].result}"
  }
}

output "obs_rtmp" {
  description = "Rückfallebene, falls SRT am Streamort nicht durchkommt."
  sensitive   = true
  value = {
    for c in var.ingest_channels :
    c.app => {
      server = "rtmp://${local.ingest_host}:1935/${c.app}"
      key    = random_password.stream_key[c.app].result
    }
  }
}

output "origin_auth" {
  description = "Wert des Headers X-Origin-Auth, zum Prüfen des Origins mit curl."
  sensitive   = true
  value       = random_password.origin_auth.result
}

output "ome_access_token" {
  description = "Zugang zur OME-Manager-API auf der VM (Port 8081, nur lokal)."
  sensitive   = true
  value       = random_password.ome_access_token.result
}

output "config_hash" {
  description = "Stand der Konfiguration in vm/. Ändert er sich, muss die VM refresh.sh laufen lassen."
  value       = local.config_hash
}
