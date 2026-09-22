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
 * @param {{id: string, title: string, slug: string}} ausgang
 * @param {string} eingangId
 * @param {Array<{id: string, hls: string, status: string}>} eingaenge
 */
export function oeffentlichesDokument(ausgang, eingangId, eingaenge) {
  const eingang = eingaenge.find((e) => e.id === eingangId);

  return {
    title: ausgang.title || ausgang.id,
    slug: ausgang.slug || ausgang.id,
    input: eingangId || null,
    hls: eingang?.hls || null,
    status: eingang?.status || 'unknown',
  };
}

// Pfade, die schon etwas anderes bedeuten: eigene Rewrites in firebase.json,
// die spätere API, und die Dateien, die unter web/public/ liegen — statische
// Dateien gewinnen vor dem Rewrite, ein Ausgang mit so einem Namen wäre also
// gar nicht erreichbar.
export const RESERVIERTE_SLUGS = [
  'admin', 'api', 'embed', 'app',
  'index', 'test', 'ausgang', 'regie', 'icon', 'manifest',
];

const SLUG_MUSTER = /^[a-z0-9][a-z0-9-]{1,30}$/;

/**
 * Prüft eine vom Admin vergebene Adresse. Gibt null zurück, wenn sie taugt,
 * sonst den Grund im Klartext.
 *
 * Die ID eines anderen Ausgangs ist verboten, weil /<id> immer direkt auf jenen
 * Ausgang zeigt — ein gleichnamiger Slug wäre unerreichbar und der Admin suchte
 * den Fehler woanders.
 *
 * @param {string} slug
 * @param {Array<{id: string, slug?: string}>} ausgaenge  alle, auch der eigene
 * @param {string} eigeneId  Ausgang, der gerade umbenannt wird
 */
export function pruefeSlug(slug, ausgaenge, eigeneId) {
  if (!slug) { return 'Die Adresse darf nicht leer sein.'; }
  if (!SLUG_MUSTER.test(slug)) {
    return 'Erlaubt sind 2 bis 31 Zeichen: Kleinbuchstaben, Ziffern und Bindestriche, '
         + 'beginnend mit Buchstabe oder Ziffer.';
  }
  if (RESERVIERTE_SLUGS.includes(slug)) { return `„${slug}“ ist für die Seite selbst reserviert.`; }

  const kollision = ausgaenge.find((a) => a.id !== eigeneId && (a.id === slug || a.slug === slug));
  if (kollision) { return `„${slug}“ gehört schon zu ${kollision.title || kollision.id}.`; }

  return null;
}
