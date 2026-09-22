# ---------------------------------------------------------------------------
# Firestore — Ausgänge, Presets und Routing (Phase 2)
# ---------------------------------------------------------------------------
# Öffentlich lesbar ist nur public/{name}. Geschrieben wird in Phase 2 direkt aus
# der Regieansicht; die Firestore-Regeln lassen das nur für die Adressen aus
# admin_emails zu. Ab Phase 3 schreibt die API, dann ändern sich nur die Regeln.

resource "google_firestore_database" "default" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  # ABANDON: "tofu destroy" baut die Media-VM ab, lässt die Datenbank aber stehen.
  # Sie enthält das Routing und kostet ohne Zugriffe praktisch nichts; ein
  # versehentliches Löschen wäre nicht rückgängig zu machen.
  deletion_policy = "ABANDON"

  depends_on = [google_project_service.required]
}

resource "google_firebaserules_ruleset" "firestore" {
  project = var.project_id

  source {
    files {
      name    = "firestore.rules"
      content = local.firestore_rules
    }
  }

  depends_on = [google_firestore_database.default]
}

resource "google_firebaserules_release" "firestore" {
  project      = var.project_id
  name         = "cloud.firestore"
  ruleset_name = google_firebaserules_ruleset.firestore.name
}

# --------------------------------------------------------------- Stammdaten
# Eingänge, Ausgänge und Presets sind Konfiguration und stehen deshalb hier als
# Code. Routing und public/{name} nicht: die ändert die Regie im Betrieb, sie
# wären sofort Drift. Ist noch kein Routing gesetzt, legt die Regieansicht es
# beim ersten Öffnen aus dem ersten Preset an.

resource "google_firestore_document" "input" {
  for_each = local.channels

  project     = var.project_id
  database    = google_firestore_database.default.name
  collection  = "inputs"
  document_id = each.key

  fields = jsonencode({
    stream = { stringValue = each.value.stream }
    hls    = { stringValue = local.playback_urls[each.key] }
    # Phase 3 setzt das per AdmissionWebhook auf "live" bzw. "offline".
    status = { stringValue = "unknown" }
  })
}

resource "google_firestore_document" "output" {
  for_each = { for i, o in var.outputs : o.name => merge(o, { order = i }) }

  project     = var.project_id
  database    = google_firestore_database.default.name
  collection  = "outputs"
  document_id = each.key

  fields = jsonencode({
    title        = { stringValue = each.value.title }
    defaultInput = { stringValue = each.value.default_input }
    order        = { integerValue = tostring(each.value.order) }
  })
}

resource "google_firestore_document" "preset" {
  for_each = local.presets

  project     = var.project_id
  database    = google_firestore_database.default.name
  collection  = "presets"
  document_id = each.key

  fields = jsonencode({
    title   = { stringValue = each.value.title }
    order   = { integerValue = tostring(each.value.order) }
    mapping = { mapValue = { fields = { for out, in_ in each.value.mapping : out => { stringValue = in_ } } } }
  })
}
