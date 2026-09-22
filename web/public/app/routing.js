// Routing: welcher Eingang läuft auf welchem Ausgang.
//
// Reine Funktionen ohne Firebase — Phase 2 ruft sie in der Regieansicht im
// Browser auf, Phase 3 ruft dieselbe Datei unverändert in der API auf, wenn das
// Schreiben dorthin wandert. Deshalb stehen hier keine Importe und keine
// Zeitstempel: serverTimestamp() gehört dem Aufrufer.

/**
 * Effektiver Eingang je Ausgang. Reihenfolge der Entscheidung:
 * Einzel-Override sticht Preset, Preset sticht Standard-Eingang des Ausgangs.
 *
 * @param {Array<{id: string, defaultInput: string}>} ausgaenge
 * @param {Array<{id: string, mapping: Object<string,string>}>} presets
 * @param {{preset?: string, overrides?: Object<string,string>}} routing
 * @returns {Object<string,string>} Ausgangsname → Eingangs-ID
 */
export function effektiveEingaenge(ausgaenge, presets, routing) {
  const preset = presets.find((p) => p.id === routing?.preset);
  const overrides = routing?.overrides || {};

  const ergebnis = {};
  for (const a of ausgaenge) {
    ergebnis[a.id] = overrides[a.id] || preset?.mapping?.[a.id] || a.defaultInput;
  }
  return ergebnis;
}

/**
 * Das Dokument, das die Ausgangsseite liest. Es ist das einzige, das ohne
 * Anmeldung lesbar ist, deshalb steht hier nur, was der Player braucht.
 *
 * Ein unbekannter Eingang ergibt bewusst kein Fehlerfall, sondern hls: null —
 * die Seite zeigt dann „kein Signal“ statt einer leeren Fläche.
 *
 * @param {{id: string, title: string}} ausgang
 * @param {string} eingangId
 * @param {Array<{id: string, hls: string, status: string}>} eingaenge
 */
export function oeffentlichesDokument(ausgang, eingangId, eingaenge) {
  const eingang = eingaenge.find((e) => e.id === eingangId);

  return {
    title: ausgang.title,
    input: eingangId || null,
    hls: eingang?.hls || null,
    status: eingang?.status || 'unknown',
  };
}
