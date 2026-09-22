// Prüft die Auflösung und die Adressvergabe, ohne sie aus der Oberfläche heraus
// durchspielen zu müssen. Läuft ohne Abhängigkeiten:
//   node web/test/routing.test.mjs
import assert from 'node:assert/strict';
import {
  effektiveEingaenge, oeffentlichesDokument, pruefeSlug,
} from '../public/app/routing.js';

const ausgaenge = [
  { id: 'output1', title: 'Großer Saal', slug: 'hauptsaal', defaultInput: 'live1' },
  { id: 'output2', title: 'Nebenraum', slug: 'nebenraum', defaultInput: 'live2' },
];

const presets = [
  { id: 'normal', mapping: { output1: 'live1', output2: 'live2' } },
  { id: 'alle-live1', mapping: { output1: 'live1', output2: 'live1' } },
];

const eingaenge = [
  { id: 'live1', hls: 'https://live.example/live1/kanal1/ts:master.m3u8', status: 'live' },
  { id: 'live2', hls: 'https://live.example/live2/kanal2/ts:master.m3u8', status: 'offline' },
];

// ------------------------------------------------------------------ Routing

// Das Preset bestimmt, solange kein Override gesetzt ist.
assert.deepEqual(
  effektiveEingaenge(ausgaenge, presets, { preset: 'alle-live1' }),
  { output1: 'live1', output2: 'live1' },
);

// Ein Override sticht das Preset, aber nur für seinen Ausgang.
assert.deepEqual(
  effektiveEingaenge(ausgaenge, presets, { preset: 'alle-live1', overrides: { output2: 'live2' } }),
  { output1: 'live1', output2: 'live2' },
);

// Ohne Routing und bei einem gelöschten Preset bleibt der Standard-Eingang —
// sonst fielen beim Aufräumen von Presets stillschweigend Seiten aus.
assert.deepEqual(
  effektiveEingaenge(ausgaenge, presets, undefined),
  { output1: 'live1', output2: 'live2' },
);
assert.deepEqual(
  effektiveEingaenge(ausgaenge, presets, { preset: 'geloescht' }),
  { output1: 'live1', output2: 'live2' },
);

// -------------------------------------------------------- Öffentliches Doku

// Es trägt die Adresse des Eingangs, nicht seinen Namen — und den Slug, über den
// die Ausgangsseite gefunden wird.
assert.deepEqual(
  oeffentlichesDokument(ausgaenge[0], 'live1', eingaenge),
  {
    title: 'Großer Saal', slug: 'hauptsaal', input: 'live1',
    hls: eingaenge[0].hls, status: 'live',
  },
);

// Zeigt ein Preset auf einen Eingang, den es nicht mehr gibt, darf die Seite
// nicht auf eine tote Adresse laufen: hls bleibt null, die Seite zeigt „kein Signal“.
assert.deepEqual(
  oeffentlichesDokument(ausgaenge[1], 'live9', eingaenge),
  { title: 'Nebenraum', slug: 'nebenraum', input: 'live9', hls: null, status: 'unknown' },
);

// Hat ein frisch angelegter Ausgang noch keinen Namen, tritt die ID ein — sonst
// stünde die Seite ohne Überschrift und wäre über nichts erreichbar.
assert.deepEqual(
  oeffentlichesDokument({ id: 'output3' }, 'live1', eingaenge),
  { title: 'output3', slug: 'output3', input: 'live1', hls: eingaenge[0].hls, status: 'live' },
);

// ------------------------------------------------------------------- Slugs

// Gültig: der eigene unveränderte Slug und ein freier neuer.
assert.equal(pruefeSlug('hauptsaal', ausgaenge, 'output1'), null);
assert.equal(pruefeSlug('kapelle', ausgaenge, 'output1'), null);
assert.equal(pruefeSlug('saal-2', ausgaenge, 'output1'), null);

// Ungültige Form.
assert.match(pruefeSlug('', ausgaenge, 'output1'), /leer/);
assert.match(pruefeSlug('Großer Saal', ausgaenge, 'output1'), /Erlaubt sind/);
assert.match(pruefeSlug('a', ausgaenge, 'output1'), /Erlaubt sind/);
assert.match(pruefeSlug('-start', ausgaenge, 'output1'), /Erlaubt sind/);

// Reserviert: die eigenen Pfade der Seite.
assert.match(pruefeSlug('admin', ausgaenge, 'output1'), /reserviert/);
assert.match(pruefeSlug('embed', ausgaenge, 'output1'), /reserviert/);
assert.match(pruefeSlug('test', ausgaenge, 'output1'), /reserviert/);

// Belegt durch einen anderen Ausgang — als Slug wie als ID. Die ID zählt mit,
// weil /<id> immer direkt dorthin zeigt und den Slug unerreichbar machen würde.
assert.match(pruefeSlug('nebenraum', ausgaenge, 'output1'), /gehört schon zu Nebenraum/);
assert.match(pruefeSlug('output2', ausgaenge, 'output1'), /gehört schon zu Nebenraum/);

// Der eigene Ausgang blockiert sich nicht selbst.
assert.equal(pruefeSlug('output1', ausgaenge, 'output1'), null);

console.log('routing.js: alle Prüfungen bestanden');
