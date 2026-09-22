#!/usr/bin/env bash
#
# Prüft die messbaren Punkte der Phase-1-Abnahme gegen die laufende Kette.
# Läuft auf dem eigenen Rechner, nicht auf der VM: Genau so sieht ein Zuschauer
# die Auslieferung — über Bunny, mit CORS und Cache.
#
# Voraussetzung: Die VM läuft und ein OBS-Stream sendet.
#
#     scripts/abnahme.sh                  # live1 / kanal1
#     scripts/abnahme.sh live2 kanal2
#
# Was das Skript NICHT kann, weil es Augen und Geräte braucht: Start, Vollbild,
# Qualitätswechsel und Zurückspulen auf den Testgeräten. Dafür die Tabelle in der
# README durchgehen; die Testseite zeigt die Messwerte je Gerät selbst an.

set -uo pipefail

APP="${1:-live1}"
STREAM="${2:-kanal1}"

BASE="${BASE:-https://live.streaming.johannwiebe.de}"
ORIGIN_BASE="${ORIGIN_BASE:-https://origin.streaming.johannwiebe.de}"
SITE_ORIGIN="${SITE_ORIGIN:-https://streaming.johannwiebe.de}"

MASTER="$BASE/$APP/$STREAM/ts:master.m3u8"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ok=0
fehl=0

# printf zählt bei %-34s Bytes, nicht Zeichen — mit Umlauten im Namen verrutscht
# die Spalte. Deshalb die Auffüllung selbst rechnen: ${#…} zählt in einer
# UTF-8-Umgebung Zeichen.
spalte() {
	printf '%s%*s' "$1" $(( 34 - ${#1} )) ''
}

# $1 Name, $2 "ja"/"nein", $3 Erläuterung
ergebnis() {
	if [ "$2" = "ja" ]; then
		printf '  \033[32mok\033[0m    %s %s\n' "$(spalte "$1")" "$3"
		ok=$(( ok + 1 ))
	else
		printf '  \033[31mFEHL\033[0m  %s %s\n' "$(spalte "$1")" "$3"
		fehl=$(( fehl + 1 ))
	fi
}

# Verweis aus einer Playlist zu einer vollen Adresse machen. Nicht einfach
# zusammenkleben: Eine Stufe darf „ts:…“ heißen, und Zeilen können absolut sein.
# $1 Verweis, $2 Adresse der Playlist, in der er steht
aufloesen() {
	case "$1" in
		http://*|https://*) printf '%s' "$1" ;;
		/*) printf '%s%s' "$(printf '%s' "$2" | sed -E 's#^(https?://[^/]+).*#\1#')" "$1" ;;
		*)  printf '%s/%s' "${2%/*}" "$1" ;;
	esac
}

hinweis() {
	printf '  --    %s %s\n' "$(spalte "$1")" "$2"
}

echo
echo "Abnahme Phase 1 — $APP/$STREAM"
echo "$MASTER"
echo

# ---------------------------------------------------------------- Erreichbar
code=$(curl -s -o "$TMP/master.m3u8" -w '%{http_code}' "$MASTER")

if [ "$code" != "200" ]; then
	ergebnis "Master-Playlist über Bunny" nein "HTTP $code — sendet OBS gerade? Läuft die VM?"
	echo
	echo "Ohne laufenden Stream sind die übrigen Prüfungen sinnlos. Abbruch."
	exit 1
fi
ergebnis "Master-Playlist über Bunny" ja "HTTP 200"

# ------------------------------------------------------------------- Stufen
stufen=$(grep -o 'RESOLUTION=[0-9x]*' "$TMP/master.m3u8" | cut -d= -f2 | sort -u | tr '\n' ' ')
fehlend=""
for soll in 1280x720 640x360 256x144; do
	case " $stufen " in
		*" $soll "*) ;;
		*) fehlend="$fehlend $soll" ;;
	esac
done

if [ -z "$fehlend" ]; then
	ergebnis "Qualitätsstufen" ja "$stufen"
else
	ergebnis "Qualitätsstufen" nein "es fehlen:$fehlend (vorhanden: $stufen)"
fi

# ---------------------------------------------------- Medien-Playlist holen
rel=$(grep -v '^#' "$TMP/master.m3u8" | grep -v '^[[:space:]]*$' | head -1 | tr -d '\r')
medien=$(aufloesen "$rel" "$MASTER")
curl -s -o "$TMP/medien.m3u8" "$medien"

# Rückstand der VM, zurückspulbare Dauer und Playlist-Typ in einem Rutsch.
# Gerechnet wird in Python: BSD-date und GNU-date sind sich bei ISO-8601 nicht einig.
python3 - "$TMP/medien.m3u8" > "$TMP/werte" <<'PYTHON'
import re, sys
from datetime import datetime, timezone

text = open(sys.argv[1], encoding='utf-8', errors='replace').read()

typ = re.search(r'#EXT-X-PLAYLIST-TYPE:\s*(\w+)', text)
print('typ=%s' % (typ.group(1) if typ else 'gleitend'))

# Nach der letzten Zeitmarke die Segmentlängen aufsummieren — das stimmt auch,
# wenn OME die Marke nur einmal am Anfang schreibt statt vor jedem Segment.
marke, danach, gesamt = None, 0.0, 0.0
for zeile in text.splitlines():
    m = re.match(r'#EXT-X-PROGRAM-DATE-TIME:\s*(\S+)', zeile)
    if m:
        roh = m.group(1).replace('Z', '+00:00')
        try:
            marke = datetime.fromisoformat(roh)
        except ValueError:
            marke = None
        danach = 0.0
        continue
    d = re.match(r'#EXTINF:\s*([\d.]+)', zeile)
    if d:
        danach += float(d.group(1))
        gesamt += float(d.group(1))

print('dauer=%.1f' % gesamt)
print('segmente=%d' % len(re.findall(r'#EXTINF:', text)))

if marke is not None:
    jetzt = datetime.now(timezone.utc)
    ende = marke.timestamp() + danach
    print('rueckstand=%.1f' % (jetzt.timestamp() - ende))
else:
    print('rueckstand=')
PYTHON

# shellcheck disable=SC1090
. "$TMP/werte"

if [ "$typ" = "EVENT" ]; then
	ergebnis "Playlist-Typ" ja "EVENT — Safari zeigt die Zeitleiste"
else
	ergebnis "Playlist-Typ" nein "$typ — im iPhone-Vollbild fehlt dann das Zurückspulen"
fi

if [ -n "$rueckstand" ]; then
	# Der Player hält nach HLS-Spezifikation drei Segmentlängen Abstand; bei 2 s
	# Segmenten sind das 6 s. Dazu rund 2 s für OBS und SRT. Bleibt die VM unter
	# 4 s, liegt die ganze Kette unter den geforderten 25 s.
	if awk "BEGIN{exit !($rueckstand < 4)}"; then
		ergebnis "Rückstand der VM" ja "$rueckstand s"
	else
		ergebnis "Rückstand der VM" nein "$rueckstand s — über 4 s wird es in der Kette eng"
	fi
else
	ergebnis "Rückstand der VM" nein "keine Zeitmarke in der Playlist"
fi

hinweis "Zurückspulbar" "$dauer s über $segmente Segmente"

# ------------------------------------------------------------ Cache-Control
cc_playlist=$(curl -sI "$MASTER" | tr -d '\r' | awk -F': ' 'tolower($1)=="cache-control"{print $2}')
case "$cc_playlist" in
	*max-age=[012]) ergebnis "Cache-Control Playlist" ja "$cc_playlist" ;;
	*) ergebnis "Cache-Control Playlist" nein "$cc_playlist — höchstens 2 s erlaubt" ;;
esac

segment=$(grep -v '^#' "$TMP/medien.m3u8" | grep -v '^[[:space:]]*$' | tail -1 | tr -d '\r')
if [ -n "$segment" ]; then
	seg_url=$(aufloesen "$segment" "$medien")
	cc_segment=$(curl -sI "$seg_url" | tr -d '\r' | awk -F': ' 'tolower($1)=="cache-control"{print $2}')
	case "$cc_segment" in
		*max-age=3600) ergebnis "Cache-Control Segment" ja "$cc_segment" ;;
		*) ergebnis "Cache-Control Segment" nein "$cc_segment — erwartet 3600" ;;
	esac

	# ------------------------------------------------------------- Bunny-Cache
	# Zweimal dasselbe Segment: Beim zweiten Mal muss es aus dem CDN kommen,
	# sonst schlägt jede Anfrage bis zur VM durch.
	curl -s -o /dev/null "$seg_url"
	sleep 1
	cache=$(curl -sI "$seg_url" | tr -d '\r' | awk -F': ' 'tolower($1)=="cdn-cache"{print $2}')
	if [ "$cache" = "HIT" ]; then
		ergebnis "Bunny liefert aus dem Cache" ja "CDN-Cache: HIT"
	else
		ergebnis "Bunny liefert aus dem Cache" nein "CDN-Cache: ${cache:-fehlt}"
	fi
else
	hinweis "Segmentprüfungen" "kein Segment in der Playlist gefunden"
fi

# --------------------------------------------------------------------- CORS
acao=$(curl -sI -H "Origin: $SITE_ORIGIN" "$MASTER" | tr -d '\r' \
	| awk -F': ' 'tolower($1)=="access-control-allow-origin"{print $2}')
if [ "$acao" = "$SITE_ORIGIN" ]; then
	ergebnis "CORS spiegelt die Herkunft" ja "$acao"
else
	ergebnis "CORS spiegelt die Herkunft" nein "bekam \"${acao:-nichts}\" statt $SITE_ORIGIN"
fi

fremd=$(curl -sI -H "Origin: https://beispiel.invalid" "$MASTER" | tr -d '\r' \
	| awk -F': ' 'tolower($1)=="access-control-allow-origin"{print $2}')
if [ -z "$fremd" ]; then
	ergebnis "CORS weist Fremde ab" ja "keine Kopfzeile für fremde Herkunft"
else
	ergebnis "CORS weist Fremde ab" nein "bekam \"$fremd\""
fi

vary=$(curl -sI -H "Origin: $SITE_ORIGIN" "$MASTER" | tr -d '\r' \
	| awk -F': ' 'tolower($1)=="vary"{print $2}')
case "$vary" in
	*Origin*|*origin*) ergebnis "Vary: Origin" ja "$vary" ;;
	*) ergebnis "Vary: Origin" nein "\"${vary:-fehlt}\" — sonst bekommt eine Herkunft die Antwort der anderen" ;;
esac

# ------------------------------------------------------------------- Origin
# Der Weg an Bunny vorbei muss zu sein. Der geheime Header kommt aus dem
# Terraform-State; fehlt er, wird nur die 403 geprüft.
origin_url="$ORIGIN_BASE/$APP/$STREAM/ts:master.m3u8"
code=$(curl -s -o /dev/null -w '%{http_code}' "$origin_url")
if [ "$code" = "403" ]; then
	ergebnis "Origin ohne Header" ja "HTTP 403"
else
	ergebnis "Origin ohne Header" nein "HTTP $code — erwartet 403"
fi

auth=$( (cd "$(dirname "$0")/../infra" && tofu output -raw origin_auth) 2>/dev/null )
if [ -n "$auth" ]; then
	code=$(curl -s -o /dev/null -w '%{http_code}' -H "X-Origin-Auth: $auth" "$origin_url")
	if [ "$code" = "200" ]; then
		ergebnis "Origin mit Header" ja "HTTP 200"
	else
		ergebnis "Origin mit Header" nein "HTTP $code — erwartet 200"
	fi
else
	hinweis "Origin mit Header" "übersprungen (tofu output nicht verfügbar)"
fi

# ---------------------------------------------------------------- Zusammenfassung
echo
if [ "$fehl" -eq 0 ]; then
	printf '  \033[32m%d Prüfungen bestanden.\033[0m\n' "$ok"
else
	printf '  \033[31m%d von %d Prüfungen gescheitert.\033[0m\n' "$fehl" "$(( ok + fehl ))"
fi

cat <<'REST'

  Offen bleibt, was nur von Hand geht — Tabelle in der README ausfüllen:
  Start, Vollbild, Qualitätswechsel und Zurückspulen je Gerät. Die Testseite
  zeigt die Verzögerung dort selbst an, Stoppuhr ist nicht nötig.
REST

[ "$fehl" -eq 0 ]
