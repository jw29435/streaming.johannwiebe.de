# streaming.johannwiebe.de

Streaming-Plattform für mehrere gleichzeitige OBS-Streams, öffentlich abspielbar auf festen
Seiten. Technik bei Google Cloud, Videoauslieferung über Bunny CDN.

**Maßgebliches Dokument: [docs/konzept.md](docs/konzept.md).** Es beschreibt Architektur,
Ausbaustufen, Datenmodell, Kosten und die fünf Bauphasen. Bei Widersprüchen zwischen diesem
CLAUDE.md und dem Konzept gilt das Konzept; Abweichungen werden hier unter
„Festlegungen aus der Recherche" begründet.

## Sprache

Projektsprache ist **Deutsch**: Dokumentation, README, Commit-Nachrichten, Kommentare und
Antworten im Chat. Bezeichner im Code (Terraform-Variablen, Dateinamen, XML-Elemente) bleiben
englisch, damit sie zu den Werkzeugen passen.

## Aktueller Stand

Phase 1 (Durchstich der Media-Pipeline). Die Infrastruktur ist ausgerollt und die Pipeline
trägt: Am 20.09.2026 kam ein OBS-Stream per SRT an, lief über Bunny als HLS und war über die
ganze Streamdauer zurückspulbar. **Die VM ist seitdem heruntergefahren**, damit sie nichts
kostet — vor dem nächsten Test starten.

Alles, was ohne fremde Geräte prüfbar ist, ist abgenommen: CPU bei zwei gleichzeitigen
Streams 31 % im Mittel und 35 % in der Spitze, Rückstand der VM 1,5–2,1 s, RTMP als
Rückfallebene, die drei Qualitätsstufen, die EVENT-Playlist und `conclude.sh`.
`scripts/abnahme.sh` prüft diese Punkte in einem Durchlauf gegen die laufende Kette und
gehört vor jeden Test.

Offen ist nur noch der Gerätedurchlauf mit laufendem Stream: Start, Vollbild,
Qualitätswechsel und Zurückspulen auf iPhone, Android, Windows (Edge, Firefox) und MacBook,
dazu die Verzögerung im echten Player. Die Testseite rechnet sie selbst aus, eine Stoppuhr
ist nicht nötig. **Ein iPad steht nicht zur Verfügung** — dieses Kriterium aus dem Konzept
bleibt offen; das iPhone prüft dieselbe WebKit-Engine, aber nicht das größere Vollbild-Layout
von iPadOS. Die Tabelle in der README hält den Stand fest.

| Phase | Inhalt | Stand |
| --- | --- | --- |
| 1 | VM mit OME und Caddy, ein Test-Eingang, Bunny, Testseite | in Arbeit |
| 2 | Web-App, feste Ausgangsseiten, Routing | offen |
| 3 | Konten, Rollen, Stream-Keys, Webhooks | offen |
| 4 | Zeitplan, Automatik, Alarme, Lasttest | offen |
| 5 | Umstieg von AVideo | offen |

## Feste Umgebung

Diese Werte sind geprüft und dürfen im Code als bekannt vorausgesetzt werden. Keine Geheimnisse.

| Sache | Wert |
| --- | --- |
| GCP-Projekt | `stream-johannwiebe-de` (Nummer `669198838164`), Abrechnung aktiv |
| Region | `europe-west3` (Frankfurt) |
| Firebase | im Projekt bereits aktiviert (`firebase.googleapis.com`, `firebasehosting.googleapis.com`) |
| Cloudflare-Zone | `johannwiebe.de`, Zone-ID `f206f3f9389944adad339c499a659321` |
| Cloudflare-Konto | `d6bb38663edd511c41971d30fb91115f` (jw29435) |
| Git-Remote | `github.com/jw29435/streaming.johannwiebe.de`, Branch `main` |

Unterhalb von `streaming.johannwiebe.de` existiert noch kein DNS-Eintrag. Alle neuen Einträge
stehen auf **DNS only** (grauer Wolke), nie auf Proxy — sonst kommen weder SRT noch die
Zertifikate von Firebase und Bunny durch.

| Name | Typ | Ziel | Zweck |
| --- | --- | --- | --- |
| `streaming.johannwiebe.de` | A/TXT laut Firebase | Firebase Hosting | Seiten |
| `live.streaming.johannwiebe.de` | CNAME | Bunny Pull Zone | Video für Zuschauer |
| `origin.streaming.johannwiebe.de` | A | IP der VM | nur Bunny holt hier ab |
| `ingest.streaming.johannwiebe.de` | A | IP der VM | Ziel für OBS |

## Aufbau des Repos

```
docs/konzept.md   Konzept, maßgeblich
infra/            OpenTofu/Terraform: VM, Firewall, Dienstkonto, Secrets, Bunny
vm/               Docker Compose, OME-Konfiguration, Caddyfile, Startskripte
web/              Testseite mit Video.js auf Firebase Hosting
scripts/          abnahme.sh: prüft die messbaren Abnahmepunkte vom eigenen Rechner aus
```

## Gepinnte Versionen

Nie `latest` verwenden. Updates nur an einem Nicht-Streamtag, mit Test.

| Bestandteil | Version | Stand |
| --- | --- | --- |
| OvenMediaEngine | `airensoft/ovenmediaengine:v0.21.0` | 2026-08-13 |
| Caddy | `caddy:2.11.4` | 2026-09-18 |
| Video.js | `8.24.1` | – |
| Bunny-Provider | `BunnyWay/bunnynet` `0.18.2` | 2026-08-26 |

## Festlegungen aus der Recherche

Ergebnisse der in der Phase-1-Aufgabe geforderten Prüfungen, jeweils an der Quelle belegt.

- **`<DVR><MaxDuration>` zählt Sekunden.** Die OME-Doku widerspricht sich: die Tabelle in
  `docs/streaming/hls.md` sagt „milliseconds", der Fließtext im selben Dokument sagt Sekunden.
  Der Quelltext entscheidet: `src/publishers/hls/hls_stream.cpp` rechnet
  `dvr_window_ms = dvr_config.GetMaxDuration() * 1000`. **10 Minuten = `600`.**
- **Safari zeigt beim gleitenden Fenster keine Zeitleiste.** OME-Doku: „Safari Native Player only
  provides the Seek UI if `#EXT-X-PLAYLIST-TYPE: EVENT` is present." Im nativen iPhone-Vollbild
  übernimmt iOS die Bedienelemente, die eigenen Video.js-Knöpfe sind dann weg. Zurückspulen im
  iPhone-Vollbild gibt es deshalb nur mit `<EventPlaylistType>true</EventPlaylistType>` — dann
  wächst die Playlist ab Streamstart und muss vor Ablauf von `MaxDuration` per
  `concludeHlsLive`-API beendet werden. Umschaltbar über die Variable `hls_event_playlist`.
- **HLS mit TS läuft unter einer eigenen Adresse:**
  `https://host/<app>/<stream>/ts:<playlist>.m3u8` (oder `…/<playlist>.m3u8?format=ts`).
  Playlistnamen dürfen nie `playlist` oder `chunklist` heißen, das sind reservierte Wörter.
- **Für TS braucht die Playlist `<Options><EnableTsPackaging>true</EnableTsPackaging></Options>`,**
  sonst liefert der HLS-Publisher nichts aus. TS kann nur Bild und Ton gemeinsam transportieren;
  reine Tonspuren gibt es hier nicht, der Nur-Ton-Modus blendet später das Bild aus.
- **Der HLS-Publisher ist laut Doku „still in development"** und unterstützt SignedPolicy und
  AdmissionWebhooks nicht. Das betrifft nur die Wiedergabe, die ohnehin öffentlich ist. Die
  Webhooks aus Phase 3 hängen am SRT-/RTMP-Provider und sind davon unberührt.
- **SRT-`streamid` lautet `{VHost}/{App}/{Stream}`,** in OBS als
  `srt://host:9999?streamid=…` mit leerem Stream-Key.
- **Es gibt einen gepflegten Bunny-Provider,** also wird die Pull Zone per Terraform angelegt.
  `cache_expiration_time = -1` bedeutet „Cache-Control des Origin beachten". Für den geheimen
  Header zum Origin gibt es kein eigenes Feld; er läuft über eine Edge Rule mit der Aktion
  `SetRequestHeader`. Origin Shield steht in Europa nur als `FR` zur Verfügung.

## Offene Schwachstelle bis Phase 3

**In Phase 1 prüft OME den Stream-Key nicht.** Nachgewiesen am 20.09.2026: Ein frei erfundener
Key wurde angenommen und als `kanal1` ausgeliefert. Der Grund ist die Bauweise — Push-Provider
nehmen jeden Streamnamen an, und `<OutputStreamName>` bildet alles auf den öffentlichen Namen ab.
Wer den App-Namen errät, kann senden.

Der Test-Key ist damit nur ein Name, keine Anmeldung. Die Trennung von Ingest- und Wiedergabe-Pfad
bleibt trotzdem richtig: Sie verhindert, dass der Key öffentlich sichtbar wird, und liefert die
Struktur, auf der Phase 3 aufsetzt.

Solange das so ist:

- Die VM zwischen den Tests heruntergefahren lassen — das ist das wirksamste Mittel.
- Wer früher schließen will, kann die Firewall-Regel `media-allow-ingest` von `0.0.0.0/0` auf die
  IP des Streamorts einschränken. Nur sinnvoll, wenn die dortige IP fest ist.
- **Phase 3 behebt es richtig:** AdmissionWebhooks prüfen den Key an der API, bevor OME den
  Stream annimmt.

## Im ersten Test gelernt

- **Die Verzögerung entsteht im Player, nicht auf der VM.** Gemessen am 20.09.2026: 23 s
  insgesamt, davon **0,9 s** Ingest, Kodierung und Segmentierung zusammen. Player halten sich
  nach HLS-Spezifikation drei Segmentlängen vom Live-Punkt fern, also 12 s bei 4-Sekunden-
  Segmenten. Der wirksame Hebel ist deshalb `hls_segment_duration`, nicht `hls_segment_count`.
  Die Umstellung auf 2 s nimmt 6 s Rückhalt heraus, erwartet sind also **rund 17 s** —
  **noch nicht nachgemessen.** Vorsicht bei der Rechnung: 0,9 s VM plus 12 s Rückhalt sind
  13 s, gemessen waren 23 s. Die fehlenden 10 s stecken in OBS, im SRT-Weg und im Puffer des
  Players und hängen nicht an der Segmentlänge. Wer weiter drücken will, muss dort ansetzen,
  nicht an OME.
- **CORS muss beide Adressen kennen.** Firebase Hosting ist immer auch unter
  `stream-johannwiebe-de.web.app` erreichbar. Caddy prüft die Herkunft gegen `site_origins`
  und spiegelt die passende zurück; Bunny variiert den Cache über die Origin-Kopfzeile, sonst
  bekäme die eine Herkunft die zwischengespeicherte Antwort der anderen.
- **Geänderte eingebundene Dateien erreichen die Container nicht von selbst.** `compose up`
  bemerkt sie nicht, und `caddy reload` übernimmt keine geänderten Umgebungsvariablen — die
  stehen im Container fest. Deshalb baut `refresh.sh` die Container neu auf statt sie neu zu
  starten, und startet sich selbst neu, wenn es sich geändert hat.
- **Die Fehlersuche gehört auf den Server.** `EXT-X-PROGRAM-DATE-TIME` in der Medien-Playlist
  gegen die Uhr gerechnet trennt sauber zwischen Server- und Player-Verzögerung. Eine
  Schätzung nach Gefühl lag um mehr als das Doppelte daneben.
- **Die EVENT-Playlist wächst, und jeder Player holt sie ganz.** Gerechnet, nicht gemessen:
  Bei 2-Sekunden-Segmenten kommen rund 1.800 Einträge je Stunde dazu; nach zwei Stunden sind
  das etwa 300 KB, die jeder Player alle 2 Sekunden neu lädt — grob ein Fünftel der
  Videomenge obendrauf. Klassisches HLS kennt keine Teilaktualisierung. Das ist der Preis
  fürs Zurückspulen im iPhone-Vollbild und ein weiterer Grund, `conclude.sh` nach jedem
  Termin laufen zu lassen: Der nächste Stream fängt wieder klein an.
- **OBS sendet 720p mit 60 fps,** nicht mit 30 wie im Konzept angenommen. Die Stufe wird
  unverändert durchgereicht, kostet also keine Rechenleistung, aber bei 3.000 kbit/s ist 60 fps
  ein Qualitätsnachteil gegenüber 30. Vor Phase 2 klären.

## Werkzeuge auf diesem Rechner

- `gcloud` (585.0.0) angemeldet als johannwiebe29@gmail.com, Standard-Anmeldedaten vorhanden.
  **Kein Standardprojekt gesetzt** — auf dem Rechner liegen 24 Projekte, deshalb trägt jeder
  Befehl `--project stream-johannwiebe-de`.
- `gh` angemeldet als jw29435.
- `tofu` 1.12.6 und `caddy` 2.11.4 installiert (Caddy nur als Syntaxprüfer für das Caddyfile).
- `node` 26.9.0, `npm` 11.19.1, `firebase` 15.30.2. Node war gegen `libada.3` gelinkt, während
  Homebrew schon `libada.4` führte; `brew reinstall node` hat 26.9.0 aus dem Quelltext gebaut
  (dauert etwa eine Stunde, es gab kein Bottle).
- **Die Firebase-CLI ist nicht angemeldet.** Sie hat eine eigene Anmeldung, `gcloud` genügt ihr
  nicht — `firebase login` öffnet den Browser und muss von Hand laufen. Ohne das geht Deploy nur
  über die Hosting-REST-API.
- `docker` fehlt lokal; gebraucht wird es nur auf der VM.

## Arbeitsweise

- **Geheimnisse gehören nie ins Repo.** Stream-Key, Cloudflare-Token, Bunny-API-Schlüssel und der
  Wert von `X-Origin-Auth` liegen in Secret Manager bzw. in lokalen `.tfvars`, die `.gitignore`
  ausschließt. Im Code stehen nur Verweise.
- **Terraform-State liegt in einem GCS-Bucket,** nicht lokal. Der Bucket wird einmalig von Hand
  angelegt (siehe README), alles Weitere ist Code.
- **Alles, was von Hand zu tun ist, steht in der README** — vollständig, in der richtigen
  Reihenfolge und mit den DNS-Einträgen als „DNS only".
- Was das Konzept als Variable vorsieht (Maschinentyp, IP-Art, Qualitätsprofil), bleibt Variable
  mit dem Startprofil als Standard. Kein Umbau, wenn eine Ausbaustufe wechselt.
- Keine Spot-VM: Google darf sie mitten im Termin abschalten.

## Abnahme von Phase 1

Fertig, wenn ein OBS-Stream per SRT ankommt und über Bunny als HLS läuft:

- in Chrome, Edge, Firefox, Android-Chrome sowie Safari auf iPhone und iPad,
- mit Vollbild, Qualitätswechsel und Zurückspulen,
- Verzögerung unter 25 Sekunden,
- VM-CPU im Startprofil unter 70 % bei zwei gleichzeitigen Test-Streams.
