# Der State liegt in einem GCS-Bucket, damit er versioniert ist und nicht auf einem
# einzelnen Rechner hängt. Der Bucket kann sich nicht selbst anlegen — er wird einmalig
# von Hand erzeugt, siehe README, Abschnitt „Schritt 2".
#
# Achtung: Im State stehen erzeugte Geheimnisse (Stream-Keys, X-Origin-Auth,
# OME-Access-Token). Der Bucket muss deshalb privat bleiben und Versionierung haben.

terraform {
  backend "gcs" {
    bucket = "stream-johannwiebe-de-tfstate"
    prefix = "phase1"
  }
}
