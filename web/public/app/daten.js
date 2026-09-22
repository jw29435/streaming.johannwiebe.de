// Zugang zu Firestore. Eine Stelle, damit Version und Konfiguration nicht in
// jeder Seite noch einmal stehen.
//
// Version fest gepinnt wie alle anderen Bestandteile auch (siehe CLAUDE.md).
import { initializeApp } from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-app.js';
import {
  collection,
  doc,
  getDoc,
  getDocs,
  getFirestore,
  onSnapshot,
  serverTimestamp,
  setDoc,
  writeBatch,
} from 'https://www.gstatic.com/firebasejs/12.19.0/firebase-firestore.js';

export { collection, doc, getDoc, onSnapshot, serverTimestamp, setDoc, writeBatch };

async function konfiguration() {
  // Firebase Hosting liefert die Konfiguration des verknüpften Projekts unter
  // /__/firebase/init.json selbst aus. Deshalb steht hier kein Schlüssel im Repo
  // und es gibt keine erzeugte Datei im Deploy. Voraussetzung ist eine im
  // Projekt registrierte Web-App — steht als Handgriff in der README.
  const antwort = await fetch('/__/firebase/init.json');
  if (!antwort.ok) {
    throw new Error(
      'Firebase-Konfiguration nicht abrufbar (/__/firebase/init.json). ' +
      'Im Projekt ist vermutlich keine Web-App registriert — siehe README, Phase 2.'
    );
  }
  return antwort.json();
}

export const app = initializeApp(await konfiguration());
export const db = getFirestore(app);

// Kleine Sammlungen — Eingänge, Ausgänge, Presets — werden ganz geladen und im
// Browser sortiert. Das erspart einen Firestore-Index für ein paar Zeilen.
export async function sammlung(name) {
  const schnappschuss = await getDocs(collection(db, name));
  return schnappschuss.docs
    .map((d) => ({ id: d.id, ...d.data() }))
    .sort((a, b) => (a.order ?? 0) - (b.order ?? 0) || a.id.localeCompare(b.id));
}
