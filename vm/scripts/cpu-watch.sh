#!/usr/bin/env bash
#
# Misst die CPU-Auslastung der VM für das Abnahmekriterium aus Phase 1:
# unter 70 % bei zwei gleichzeitigen Test-Streams im Startprofil.
#
#     sudo /opt/media/scripts/cpu-watch.sh [Minuten]     # Standard: 10
#
# Am Ende stehen Mittelwert und Spitzenwert. Gemessen wird über /proc/stat,
# also die tatsächliche Auslastung aller Kerne, nicht die eines einzelnen.

set -euo pipefail

MINUTES=${1:-10}
INTERVAL=5
SAMPLES=$(( MINUTES * 60 / INTERVAL ))

cpu_fields() {
	# user nice system idle iowait irq softirq steal
	awk '/^cpu /{print $2+$3+$4+$6+$7+$8+$9, $2+$3+$4+$5+$6+$7+$8+$9}' /proc/stat
}

echo "Messung über $MINUTES Minuten, alle $INTERVAL Sekunden ein Wert."
echo "Kerne: $(nproc)   Start: $(date -Is)"
echo

read -r prev_busy prev_total < <(cpu_fields)

sum=0
peak=0
count=0

for _ in $(seq 1 "$SAMPLES"); do
	sleep "$INTERVAL"
	read -r busy total < <(cpu_fields)

	d_busy=$(( busy - prev_busy ))
	d_total=$(( total - prev_total ))
	prev_busy=$busy
	prev_total=$total

	[ "$d_total" -le 0 ] && continue

	pct=$(( 100 * d_busy / d_total ))
	sum=$(( sum + pct ))
	count=$(( count + 1 ))
	[ "$pct" -gt "$peak" ] && peak=$pct

	printf '%s  CPU %3d %%\n' "$(date +%H:%M:%S)" "$pct"
done

echo
if [ "$count" -gt 0 ]; then
	printf 'Mittelwert: %d %%   Spitze: %d %%\n' "$(( sum / count ))" "$peak"
	if [ "$peak" -lt 70 ]; then
		echo "Kriterium erfüllt: durchgehend unter 70 %."
	else
		echo "Kriterium verfehlt: Spitze bei $peak %. Nächster Schritt laut Konzept:"
		echo "machine_type auf c3-standard-8 und quality_profile prüfen."
	fi
else
	echo "Keine Messwerte."
fi
