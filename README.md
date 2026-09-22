# streaming.johannwiebe.de

Ein OBS-Stream kommt per SRT an, OvenMediaEngine rechnet ihn in mehrere Stufen um, Caddy
liefert ihn als HLS aus, Bunny CDN verteilt ihn, und feste Seiten auf Firebase Hosting spielen
ihn ab — mit Zurückspulen. Welcher Eingang auf welcher Seite läuft, schaltet die Regie.

**Phase 1** (Media-Pipeline) und **Phase 2** (Ausgangsseiten und Routing) stehen.

```
OBS ──SRT/RTMP──▶ Media-VM (europe-west3) ──HLS──▶ Bunny CDN ──▶ Zuschauer
                  OvenMediaEngine + Caddy           Origin Shield
```

Das vollständige Konzept steht in [docs/konzept.md](docs/konzept.md), der Projektkontext in
[CLAUDE.md](CLAUDE.md).

| Name | Wofür |
| --- | --- |
| `ingest.streaming.johannwiebe.de` | Ziel für OBS (SRT 9999/udp, RTMP 1935/tcp) |
| `origin.streaming.johannwiebe.de` | nur Bunny holt hier ab, alles andere bekommt 403 |
| `live.streaming.johannwiebe.de` | Video für Zuschauer |
| `streaming.johannwiebe.de` | Seiten auf Firebase Hosting |

Die Seiten darunter:

| Adresse | Wofür |
| --- | --- |
| `/<ausgang>` | feste Zuschauerseite, z. B. `/hauptsaal`. Die Adresse ändert sich nie. |
| `/embed/<ausgang>` | dieselbe Seite ohne Drumherum, für `<iframe>` |
| `/admin/regie` | Regieansicht: Preset tippen, einzeln schalten |
| `/` | Übersicht aller Ausgänge |
| `/test` | Testseite aus Phase 1 mit den Messwerten |

---

## Voraussetzungen

**Konten, die schon stehen:** Google Cloud (`stream-johannwiebe-de`, Abrechnung aktiv, Firebase
hinzugefügt), Cloudflare mit der Zone `johannwiebe.de`, GitHub.

**Was noch fehlt:** ein Bunny-Konto mit automatischer Aufladung — anlegen unter
[bunny.net](https://bunny.net), dann unter *Account → API* den API-Schlüssel kopieren.

**Werkzeuge auf dem eigenen Rechner:**

```bash
brew install opentofu
npm install -g firebase-tools

gcloud auth login
gcloud auth application-default login

# Die Firebase-CLI hat eine eigene Anmeldung, gcloud genügt ihr nicht.
# Öffnet den Browser, muss also von Hand laufen:
firebase login
```

Ein Standardprojekt für `gcloud` wird bewusst nicht gesetzt — auf diesem Rechner liegen zwei
Dutzend Projekte. Alle Befehle hier tragen `--project stream-johannwiebe-de`.

---

## Schritt 1 — Bucket für den Terraform-State

Der Bucket kann sich nicht selbst anlegen, deshalb einmalig von Hand. Versionierung ist wichtig:
Im State stehen die erzeugten Geheimnisse.

```bash
gcloud storage buckets create gs://stream-johannwiebe-de-tfstate \
  --project=stream-johannwiebe-de \
  --location=europe-west3 \
  --uniform-bucket-level-access \
  --public-access-prevention

gcloud storage buckets update gs://stream-johannwiebe-de-tfstate --versioning
```

## Schritt 2 — Cloudflare-Token ausstellen

Cloudflare → *Mein Profil* → *API-Tokens* → *Token erstellen* → Vorlage **DNS bearbeiten**.

| Feld | Wert |
| --- | --- |
| Berechtigungen | Zone · DNS · Bearbeiten |
| Zonenressourcen | Einschließen · Bestimmte Zone · **johannwiebe.de** |

Mehr darf der Token nicht dürfen: Die VM benutzt ihn beim Booten, um ihre wechselnde IP
einzutragen.

## Schritt 3 — Zugangsdaten eintragen

```bash
cd infra
cp terraform.tfvars.example terraform.tfvars
```

In `terraform.tfvars` nur diese beiden Werte setzen:

```hcl
cloudflare_api_token = "…"
bunny_api_key        = "…"
```

Für Phase 2 kommen zwei optionale Werte dazu. Ohne sie gelten die Standardwerte aus
`variables.tf` — zwei Ausgänge `hauptsaal` und `nebenraum` und eine Admin-Adresse:

```hcl
outputs = [
  { name = "hauptsaal", title = "Hauptsaal", default_input = "live1" },
  { name = "nebenraum", title = "Nebenraum", default_input = "live2" },
]
admin_emails = ["johannwiebe29@gmail.com"]
```

**Der Name eines Ausgangs steht in seiner Adresse und wird später nicht mehr geändert** —
verteilte Links sollen weiter stimmen. `admin`, `api` und `embed` sind reserviert.

Die Stream-Keys, der Wert von `X-Origin-Auth` und das OME-Access-Token werden **erzeugt**, landen
in Secret Manager und lassen sich später mit `tofu output` abrufen. Die Datei `terraform.tfvars`
schließt `.gitignore` aus und gehört nie ins Repo.

## Schritt 4 — Ausrollen

```bash
cd infra
tofu init
tofu plan          # anschauen: VM, Firewall, Secrets, Bunny Pull Zone, DNS,
                   # Firestore mit Regeln, Eingänge, Ausgänge und Presets
tofu apply
```

Ab hier läuft die VM und kostet Geld (Startprofil: rund 0,20 $ pro Stunde Laufzeit plus Disk).

> **Wenn `bunnynet_pullzone_hostname` beim ersten Lauf scheitert:** Bunny stellt das Zertifikat
> erst aus, wenn der CNAME `live.streaming.johannwiebe.de` weltweit sichtbar ist. Ein paar Minuten
> warten und `tofu apply` wiederholen.

Danach die Zugangsdaten ansehen:

```bash
tofu output playback_urls
tofu output -raw origin_auth
tofu output -json obs_srt_urls | jq
```

## Schritt 5 — DNS prüfen

Terraform legt `live` immer an, `origin` und `ingest` nur bei fester IP. Im Startprofil
(`ip_type = "ephemeral"`) trägt die **VM sie beim Booten selbst** ein — nach dem ersten Start
müssen sie da sein.

| Name | Typ | Ziel | Proxy |
| --- | --- | --- | --- |
| `streaming.johannwiebe.de` | A und TXT | laut Firebase-Konsole | **DNS only** |
| `live.streaming.johannwiebe.de` | CNAME | `streaming-johannwiebe-de.b-cdn.net` | **DNS only** |
| `origin.streaming.johannwiebe.de` | A | IP der VM | **DNS only** |
| `ingest.streaming.johannwiebe.de` | A | IP der VM | **DNS only** |

**Alle vier stehen auf „DNS only" — graue Wolke, nicht orange.** Über den Cloudflare-Proxy käme
weder SRT durch noch ließen sich die Zertifikate von Firebase, Caddy und Bunny ausstellen.

```bash
dig +short origin.streaming.johannwiebe.de
dig +short ingest.streaming.johannwiebe.de
dig +short live.streaming.johannwiebe.de
```

Steht nichts da, war die VM noch nicht fertig:

```bash
gcloud compute ssh media-vm --zone europe-west3-c --tunnel-through-iap \
  --command 'sudo tail -50 /var/log/media-refresh.log'
```

## Schritt 6 — Origin prüfen

Erst ohne, dann mit dem geheimen Header:

```bash
URL=https://origin.streaming.johannwiebe.de/live1/kanal1/ts:master.m3u8

curl -sI "$URL" | head -1
# erwartet: HTTP/2 403

curl -sI -H "X-Origin-Auth: $(cd infra && tofu output -raw origin_auth)" "$URL" | head -1
# erwartet: HTTP/2 404, solange kein Stream läuft — die 403 ist weg, das genügt
```

## Schritt 7 — Firebase einrichten

Was sich nicht als Code abbilden lässt, in der
[Firebase-Konsole](https://console.firebase.google.com/project/stream-johannwiebe-de).

**a) Eigene Domain.** *Hosting* → *Benutzerdefinierte Domain hinzufügen* →
`streaming.johannwiebe.de`. Firebase nennt einen TXT-Eintrag zur Bestätigung und zwei
A-Einträge — beide bei Cloudflare als **DNS only** anlegen.

**b) Google-Anmeldung einschalten.** *Authentication* → *Sign-in method* → **Google** →
aktivieren. Das ist die Anmeldung für die Regieansicht. Wer sie bedienen darf, steht in
`admin_emails` (siehe Schritt 3) — ohne Eintrag dort kommt man zwar hinein, kann aber nichts
schalten.

**c) Nur falls nötig: Web-App registrieren.** Die Seiten holen ihre Firebase-Konfiguration
unter `/__/firebase/init.json`, das Firebase Hosting selbst ausliefert — deshalb steht kein
Schlüssel im Repo. Am 22.09.2026 lieferte das Projekt dort bereits `apiKey`, `authDomain` und
`projectId`, **obwohl keine Web-App registriert ist**; das genügt für Firestore und die
Anmeldung. Prüfen:

```bash
curl -s https://stream-johannwiebe-de.web.app/__/firebase/init.json
```

Fehlt dort `apiKey`, dann *Projektübersicht* → *App hinzufügen* → **Web** (`</>`), Name z. B.
`streaming`. Der angezeigte SDK-Schnipsel wird nicht gebraucht, nur die Registrierung.

## Schritt 8 — Seiten ausliefern

```bash
cd web
firebase deploy --only hosting
```

Die Seiten liegen danach auf `https://stream-johannwiebe-de.web.app` und, sobald die Domain
bestätigt ist, zusätzlich auf `https://streaming.johannwiebe.de`.

Beim **ersten Mal** einmal `/admin/regie` öffnen und anmelden: Ist noch kein Routing gesetzt,
legt die Regie es aus dem ersten Preset an und schreibt damit die Ausgangsseiten. Vorher zeigen
sie „kein Signal“.

> Falls die CLI klemmt, geht es auch ohne sie: Firebase Hosting hat eine REST-API
> (`sites/…/versions` anlegen, `:populateFiles`, Datei per `sha256` des **gzip**-Inhalts
> hochladen, `FINALIZED` setzen, `releases` anlegen). Nützlich, wenn node gerade nicht läuft.

## Schritt 9 — OBS einrichten

```bash
cd infra && tofu output -json obs_srt_urls | jq -r '.live1'
```

*Einstellungen → Stream → Dienst „Benutzerdefiniert"*:

| Feld | Wert |
| --- | --- |
| Server | `srt://ingest.streaming.johannwiebe.de:9999?streamid=default/live1/…` |
| Stream-Key | **leer lassen** (bei SRT steckt alles in der `streamid`) |

*Ausgabe → Erweitert*:

| Einstellung | Wert |
| --- | --- |
| Kodierer | x264 |
| Bitratensteuerung | CBR |
| Bitrate | 3000 kbit/s |
| Keyframe-Intervall | 2 s |
| Auflösung | 1280 × 720 |
| Bildrate | 30 fps |
| Ton | AAC, 48 kHz, 128 kbit/s |

Unter *Erweitert → Netzwerk* das automatische Wiederverbinden einschalten. Am Streamort braucht
es mindestens 6 Mbit/s stabilen Upload je Eingang.

Für RTMP als Rückfallebene: `tofu output -json obs_rtmp | jq` — dort stehen Server und Key
getrennt.

---

## Abnahme Phase 1

Fertig ist Phase 1, wenn alles hier zutrifft. Was sich messen lässt, misst ein Skript. Es
läuft auf dem eigenen Rechner und sieht die Kette dabei genau so wie ein Zuschauer — über
Bunny, mit CORS und Cache. Die VM muss laufen und OBS senden:

```bash
scripts/abnahme.sh              # live1 / kanal1
scripts/abnahme.sh live2 kanal2
```

Geprüft werden: Erreichbarkeit über Bunny, die drei Qualitätsstufen, der Playlist-Typ, der
Rückstand der VM aus `EXT-X-PROGRAM-DATE-TIME`, Cache-Control für Playlists und Segmente,
der Bunny-Cache, CORS für erlaubte und fremde Herkünfte sowie die 403 am Origin.

**CPU messen** — zwei Streams gleichzeitig senden, dann auf der VM:

```bash
gcloud compute ssh media-vm --zone europe-west3-c --tunnel-through-iap \
  --command 'sudo /opt/media/scripts/cpu-watch.sh 10'
```

Ziel: dauerhaft unter 70 %.

**Geräte durchgehen** und das Ergebnis hier eintragen. Die Verzögerung steht dabei auf der
Testseite selbst, Zeile „Verzögerung ab der VM" — eine Stoppuhr ist nicht nötig. Dazu kommen
rund 2 s für OBS und SRT; das Kriterium von 25 s gilt für die ganze Kette, deshalb warnt die
Seite schon ab 23 s.

| Gerät | Start | Qualitätswechsel | Vollbild | Zurückspulen | Verzögerung |
| --- | --- | --- | --- | --- | --- |
| Mac · Chrome | ✅ 20.09. | offen | offen | ✅ 20.09. | 23 s (bei 4 s Segmenten) |
| Mac · Safari | offen | offen | offen | offen | |
| Windows · Edge | ✅ 22.09. | ✅ 22.09. | ✅ 22.09. | ✅ 22.09. | nicht notiert |
| Windows · Firefox | ✅ 22.09. | ✅ 22.09. | ✅ 22.09. | ✅ 22.09. | nicht notiert |
| Android-Handy · Chrome | offen | offen | offen | offen | |
| Android-Tablet · Chrome | offen | offen | offen | offen | |
| iPhone · Safari | ✅ 22.09. | entfällt | ✅ 22.09. | ✅ 22.09. | nicht notiert |
| iPad · Safari | **kein Gerät vorhanden** | – | – | – | – |

Am 22.09.2026 liefen Windows (Edge und Firefox) und das iPhone durch — **das iPhone
im Vollbild mit Zeitleiste**, also trägt die EVENT-Playlist wie vorgesehen. Die
Verzögerung wurde dabei nicht abgelesen; der Wert aus der Umstellung auf 2-Sekunden-
Segmente (erwartet rund 17 s) ist damit **weiterhin unbestätigt**. Offen bleiben
Android und Mac · Safari.

Auf iPhone und iPad gibt es kein Qualitätsmenü: Safari spielt HLS selbst ab und wählt die Stufe
allein, deshalb steht dort „entfällt". Die Zeitleiste im Vollbild erscheint dort nur, weil die
Playlist vom Typ `EVENT` ist.

**Das iPad bleibt offen**, weil keines da ist. Das iPhone prüft dieselbe WebKit-Engine, aber
nicht das größere Vollbild-Layout von iPadOS. Wer eines auftreibt, trägt die Zeile nach; bis
dahin ist dieser Punkt aus dem Konzept ungeprüft.

### Stand der Abnahme (20.09.2026)

Serverseitig geprüft und erfüllt:

| Kriterium | Ergebnis |
| --- | --- |
| Stream kommt per SRT an, HLS über Bunny | ✅ mit echtem OBS |
| RTMP als Rückfallebene | ✅ beide Kanäle |
| Mehrere Qualitätsstufen | ✅ 720p, 360p, 144p |
| Zurückspulen über die Streamdauer | ✅ `EXT-X-PLAYLIST-TYPE: EVENT` |
| **CPU bei zwei Streams unter 70 %** | ✅ **31 % Mittel, 35 % Spitze** |
| `conclude.sh` beendet die Playlist | ✅ setzt `EXT-X-ENDLIST` |
| Origin ohne geheimen Header | ✅ 403 |
| Port 13333 von außen, SSH | ✅ dicht, nur über IAP |

**Zur Verzögerung.** Zuerst gemessen: 23 s insgesamt, davon nur 0,9 s auf der VM. Der Rest ist
Rückhalt im Player, der sich nach HLS-Spezifikation drei Segmentlängen vom Live-Punkt fernhält —
bei 4 s Segmenten also 12 s. Deshalb `hls_segment_duration` auf 2 gesenkt; der Rückhalt sinkt
damit auf 6 s, der Server liegt bei 1,5–2,1 s. **Im echten Player noch nicht nachgemessen** —
erster Punkt beim nächsten Test.

Erwartet sind rund 17 s, nicht 8–10 s: 0,9 s VM plus 12 s Rückhalt ergeben 13 s, gemessen
waren aber 23 s. Die Lücke von 10 s steckt in OBS, im SRT-Weg und im Puffer des Players und
schrumpft nicht mit der Segmentlänge. Von 23 s gehen also 6 s ab, mehr nicht.

So trennt man Server- von Player-Verzögerung, ohne zu raten: Die Medien-Playlist enthält je
Segment ein `#EXT-X-PROGRAM-DATE-TIME`. Das Ende des letzten Segments gegen die Uhr gerechnet
ergibt den Rückstand der VM; alles darüber hinaus ist Player. Diese Rechnung machen
`scripts/abnahme.sh` und die Testseite inzwischen selbst — von Hand nachrechnen muss das
niemand mehr.

### Sicherheitshinweis zu Phase 1

**Der Stream-Key wird noch nicht geprüft.** Ein erfundener Key wurde angenommen und ausgeliefert —
Push-Provider nehmen jeden Streamnamen an. Wer den App-Namen errät, kann senden. Deshalb die VM
zwischen den Tests heruntergefahren lassen; Phase 3 behebt es mit AdmissionWebhooks.

---

## Abnahme Phase 2

Fertig, wenn ein Preset auf allen offenen Seiten in unter 5 Sekunden wirkt — auch auf einem
iPhone im Vollbild.

So wird gemessen, ohne Stoppuhr: zwei Geräte nebeneinander auf `/hauptsaal`, ein drittes auf
`/admin/regie`. Preset tippen und zählen, bis beide Seiten das neue Bild zeigen. Firestore
meldet die Änderung in der Regel unter einer Sekunde; der Rest ist die Ladezeit des Players.

| Prüfpunkt | Stand |
| --- | --- |
| Preset wirkt auf allen offenen Seiten in unter 5 s | offen |
| Einzel-Override sticht das Preset, nur für seinen Ausgang | offen |
| Umschalten im iPhone-Vollbild | offen — siehe unten |
| `/embed/<ausgang>` im `<iframe>` | offen |
| Ohne Signal: Hinweis statt schwarzer Fläche, Start von selbst | offen |
| Nur-Ton-Modus | offen |
| AirPlay (Safari) und Chromecast (Chrome) | offen |
| Ohne Anmeldung ist nur `public/*` lesbar | offen |
| Fremde Anmeldung kann nicht schalten | offen |

Die Auflösung selbst — Preset, Override, Standard-Eingang — hängt nicht am Gerät und wird
deshalb hier geprüft:

```bash
node web/test/routing.test.mjs
```

### Bekannte Einschränkung: iPhone im Vollbild

Im nativen Vollbild übernimmt iOS die Bedienelemente des Video-Elements. Ein Quellenwechsel
setzt dieses Element neu — und iOS beendet dabei in der Regel das Vollbild. Die Seite merkt
sich den Zustand und ruft nach `loadedmetadata` sofort `webkitEnterFullscreen()` auf; ob das
ohne neue Nutzergeste durchgeht, entscheidet iOS und ändert sich zwischen Versionen.

Mehr ist von der Webseite aus nicht möglich: Vollbild lässt sich auf dem iPhone nur für
Video-Elemente auslösen ([WebKit-Bug 212934](https://bugs.webkit.org/show_bug.cgi?id=212934)),
und eine Geste lässt sich nicht erfinden. **Beim Gerätetest festhalten, was tatsächlich
passiert** — bleibt das Vollbild, ist der Punkt erledigt; fällt es heraus, ist ein Tipp auf den
Vollbildknopf nötig, und das gehört in die Anleitung für die Zuschauer.

---

## Betrieb

### Umschalten

`/admin/regie` auf dem Handy, mit Google anmelden. Oben die Presets als Knöpfe, darunter je
Ausgang ein Auswahlfeld für den Einzelfall. Beides schreibt in einem Zug das Routing und alle
Ausgangsseiten — es gibt keinen Zwischenzustand, in dem eine Seite schon und eine andere noch
nicht umgeschaltet hat.

Ein Preset-Knopf löscht die Einzelfälle mit. Wer nur einen Ausgang umlegt, behält das Preset,
und der Knopf ist dann nicht mehr hervorgehoben — das ist gewollt: Es zeigt, dass jemand
danebengegriffen hat.

**Eingänge zeigen bis Phase 3 „Status erst ab Phase 3".** Ob OBS wirklich sendet, meldet erst
der AdmissionWebhook aus Phase 3. Bis dahin sagt die Ausgangsseite es indirekt: Läuft ein Bild,
sendet jemand.

### Nach jedem Termin: Playlist beenden

Solange `hls_event_playlist = true` gilt, wächst die Playlist ab Streamstart. Sie muss vor Ablauf
von `hls_dvr_max_duration` (4 Stunden) beendet werden, sonst reagiert vor allem Safari
unvorhersehbar.

Der zweite Grund ist die Datenmenge: Bei 2-Sekunden-Segmenten kommen rund 1.800 Einträge je
Stunde dazu, und klassisches HLS kennt keine Teilaktualisierung — jeder Player lädt alle
2 Sekunden die ganze Playlist neu. Nach dem Beenden fängt der nächste Stream wieder klein an.

```bash
gcloud compute ssh media-vm --zone europe-west3-c --tunnel-through-iap \
  --command 'sudo /opt/media/scripts/conclude.sh'
```

Ab Phase 4 übernimmt das die Automatik.

### Vor jedem Test: VM starten

Zwischen den Terminen ist sie aus. Nach dem Start dauert es etwa eine Minute, bis die VM ihre
neue IP bei Cloudflare eingetragen hat und die Container laufen.

```bash
gcloud compute instances start media-vm --zone europe-west3-c --project stream-johannwiebe-de

# warten, bis die DNS-Einträge stimmen:
watch -n5 'dig +short origin.streaming.johannwiebe.de'
```

### VM anhalten und starten

Zwischen den Terminen kostet nur die Disk. Beim Startprofil ändert sich die IP bei jedem Start —
die VM trägt sie selbst neu ein, das dauert etwa eine Minute.

```bash
gcloud compute instances stop  media-vm --zone europe-west3-c
gcloud compute instances start media-vm --zone europe-west3-c
```

### Konfiguration ändern

Alles unter `vm/` liegt im Konfig-Bucket, nicht auf der Maschine. Also:

```bash
cd infra && tofu apply                     # lädt die neue Fassung in den Bucket
gcloud compute ssh media-vm --zone europe-west3-c --tunnel-through-iap \
  --command 'sudo /opt/media/refresh.sh'   # holt sie und startet die Container neu
```

Dateien auf der VM direkt zu bearbeiten bringt nichts: Der nächste Start überschreibt sie.

### Ausbaustufe wechseln

In `infra/terraform.tfvars` setzen und `tofu apply` — an einem Nicht-Streamtag.

```hcl
machine_type    = "c3-standard-8"
ip_type         = "static"
quality_profile = "normal"
```

---

## Fehlersuche

| Beobachtung | Woran es meist liegt |
| --- | --- |
| OBS verbindet nicht | `streamid` falsch kopiert, oder die VM ist aus. `dig +short ingest.…` prüfen. |
| Caddy hat kein Zertifikat | Der A-Eintrag für `origin` zeigt noch nicht auf die VM, oder er steht auf Proxy statt „DNS only". |
| Bunny liefert 403 | Die Edge Rule mit `X-Origin-Auth` fehlt oder der Wert passt nicht mehr — `tofu apply`. |
| Playlist ist leer | `EnableTsPackaging` fehlt, oder OBS sendet H.265 statt H.264. |
| Verzögerung über 25 s | `hls_segment_count` auf 4 senken, SRT-Latenz in OBS auf 2 s, dann neu messen. |
| Safari zeigt keine Zeitleiste | `hls_event_playlist` steht auf `false`. Beim gleitenden Fenster gibt es sie nicht. |
| Seiten bleiben leer, Konsole meldet `init.json` | Es ist keine Web-App im Firebase-Projekt registriert — Schritt 7b. |
| Regie meldet „darf nicht schalten" | Die angemeldete Adresse fehlt in `admin_emails`. Eintragen, `tofu apply`, neu laden. |
| Ausgangsseite sagt „Unbekannter Ausgang" | Es gibt kein `public/<name>` — einmal in der Regie ein Preset tippen. |
| Umschalten wirkt nicht | Firestore-Regeln greifen erst nach `tofu apply`; in der Browser-Konsole steht `permission-denied`. |
| `tofu apply`: „requires a quota project" | Fehlt `user_project_override` im google-Provider, oder die Anmeldedaten haben kein Kontingentprojekt. Beides deckt `providers.tf` ab. |
| `tofu`: „could not find default credentials" | `gcloud auth application-default login` fehlt. Für einen einzelnen Lauf reicht `GOOGLE_OAUTH_ACCESS_TOKEN="$(gcloud auth print-access-token)"` vor dem Befehl. |

Logbücher:

```bash
gcloud compute ssh media-vm --zone europe-west3-c --tunnel-through-iap
sudo tail -f /var/log/media-refresh.log     # Booten, DNS, Container
sudo docker logs -f ome                     # Ingest und Transcoding
sudo docker logs -f caddy                   # Zugriffe von Bunny
sudo docker compose -f /opt/media/docker-compose.yml ps
```

## Alles wieder abbauen

```bash
cd infra && tofu destroy
```

Der State-Bucket und die von Hand angelegte Firebase-Domain bleiben; beide bei Bedarf in der
Konsole entfernen. **Die Firestore-Datenbank bleibt ebenfalls stehen** (`deletion_policy =
"ABANDON"`): Sie enthält das Routing, kostet ohne Zugriffe praktisch nichts, und ein
versehentliches Löschen wäre nicht rückgängig zu machen.
