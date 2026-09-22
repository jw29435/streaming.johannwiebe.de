# Feste IP nur im Normalprofil. Im Startprofil spart die wechselnde IP rund 7 $ im Monat;
# die VM trägt sie dann beim Booten selbst bei Cloudflare ein.
resource "google_compute_address" "media" {
  count = var.ip_type == "static" ? 1 : 0

  name         = "media-vm-ip"
  region       = var.region
  address_type = "EXTERNAL"

  depends_on = [google_project_service.required]
}

resource "google_compute_instance" "media" {
  name         = "media-vm"
  machine_type = var.machine_type
  zone         = var.zone
  tags         = ["media-vm"]
  description  = "OvenMediaEngine und Caddy, Phase 1"

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = var.disk_size_gb
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.media.id

    access_config {
      # Bei wechselnder IP bleibt das leer, Google vergibt dann eine.
      nat_ip = var.ip_type == "static" ? google_compute_address.media[0].address : null
    }
  }

  service_account {
    email = google_service_account.media_vm.email
    # cloud-platform in Verbindung mit einem Dienstkonto ohne Projektrollen:
    # Was die VM darf, entscheidet allein die IAM-Zuweisung, nicht der Scope.
    scopes = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  scheduling {
    # Ausdrücklich keine Spot-VM: Google dürfte sie mitten im Termin abschalten.
    provisioning_model  = "STANDARD"
    preemptible         = false
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }

  metadata = {
    enable-oslogin = "TRUE"
    config-hash    = local.config_hash

    startup-script = templatefile("${path.module}/../vm/scripts/startup.sh.tftpl", {
      config_bucket = local.config_bucket
    })
  }

  allow_stopping_for_update = true

  depends_on = [
    google_storage_bucket_object.config,
    google_secret_manager_secret_version.generated,
    google_secret_manager_secret_version.cloudflare_dns_token,
    google_secret_manager_secret_iam_member.vm_reads_generated,
    google_secret_manager_secret_iam_member.vm_reads_cloudflare_token,
    google_storage_bucket_iam_member.vm_reads_config,
  ]

  lifecycle {
    # Die wechselnde IP ändert sich bei jedem Start — das ist kein Grund,
    # die Maschine neu zu bauen.
    ignore_changes = [network_interface[0].access_config[0].nat_ip]
  }
}
