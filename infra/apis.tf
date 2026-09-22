# Firebase und Firebase Hosting sind im Projekt bereits aktiv, die fehlen hier bewusst.

resource "google_project_service" "required" {
  for_each = toset([
    "compute.googleapis.com",
    "iap.googleapis.com",
    "secretmanager.googleapis.com",
    "storage.googleapis.com",
    "oslogin.googleapis.com",
    "firestore.googleapis.com",
    # Fürs Dienstkonto der VM. Stand nie in dieser Liste und war im Projekt nicht
    # aktiviert — aufgefallen erst, als der Provider anfing, das Kontingent gegen
    # dieses Projekt zu buchen (user_project_override in providers.tf).
    "iam.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  # Beim Zerstören bleiben die APIs an: Abschalten würde auch Dinge treffen,
  # die nicht zu dieser Phase gehören.
  disable_on_destroy = false
}
