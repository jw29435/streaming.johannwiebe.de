// Prüft die Auflösung, ohne die aus der Oberfläche heraus durchspielen zu müssen.
// Läuft ohne Abhängigkeiten:   node web/test/routing.test.mjs
import assert from 'node:assert/strict';
import { effektiveEingaenge, oeffentlichesDokument } from '../public/app/routing.js';

const ausgaenge = [
  { id: 'hauptsaal', title: 'Hauptsaal', defaultInput: 'live1' },
  { id: 'nebenraum', title: 'Nebenraum', defaultInput: 'live2' },
];

const presets = [
  { id: 'normal', mapping: { hauptsaal: 'live1', nebenraum: 'live2' } },
  { id: 'alle-live1', mapping: { hauptsaal: 'live1', nebenraum: 'live1' } },
];

const eingaenge = [
  { id: 'live1', hls: 'https://live.example/live1/kanal1/ts:master.m3u8', status: 'live' },
  { id: 'live2', hls: 'https://live.example/live2/kanal2/ts:master.m3u8', status: 'offline' },
];

// Das Preset bestimmt, solange kein Override gesetzt ist.
assert.deepEqual(
  effektiveEingaenge(ausgaenge, presets, { preset: 'alle-live1' }),
  { hauptsaal: 'live1', nebenraum: 'live1' },
);

// Ein Override sticht das Preset, aber nur für seinen Ausgang.
assert.deepEqual(
  effektiveEingaenge(ausgaenge, presets, { preset: 'alle-live1', overrides: { nebenraum: 'live2' } }),
  { hauptsaal: 'live1', nebenraum: 'live2' },
);

// Ohne Routing und bei einem gelöschten Preset bleibt der Standard-Eingang —
// sonst fielen beim Aufräumen von Presets stillschweigend Seiten aus.
assert.deepEqual(
  effektiveEingaenge(ausgaenge, presets, undefined),
  { hauptsaal: 'live1', nebenraum: 'live2' },
);
assert.deepEqual(
  effektiveEingaenge(ausgaenge, presets, { preset: 'geloescht' }),
  { hauptsaal: 'live1', nebenraum: 'live2' },
);

// Das öffentliche Dokument trägt die Adresse des Eingangs, nicht seinen Namen.
assert.deepEqual(
  oeffentlichesDokument(ausgaenge[0], 'live1', eingaenge),
  { title: 'Hauptsaal', input: 'live1', hls: eingaenge[0].hls, status: 'live' },
);

// Zeigt ein Preset auf einen Eingang, den es nicht mehr gibt, darf die Seite
// nicht auf eine tote Adresse laufen: hls bleibt null, die Seite zeigt „kein Signal“.
assert.deepEqual(
  oeffentlichesDokument(ausgaenge[1], 'live9', eingaenge),
  { title: 'Nebenraum', input: 'live9', hls: null, status: 'unknown' },
);

console.log('routing.js: alle Prüfungen bestanden');
