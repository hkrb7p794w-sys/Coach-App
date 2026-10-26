/**
 * Schutz gegen erfundene Inhalte: Die KI formuliert nur, was die App als Fakten schickt.
 *
 * 1. Systemanweisung: nur Fakten aus der Anfrage, keine neuen Zahlen, Einheiten oder Quellen.
 * 2. Prüfung der Antwort: Jede Zahl in einem Punkt muss in der Anfrage vorkommen (0–3 sind als
 *    Zählwörter frei), genannte Quellen müssen zu den mitgeschickten Regeln gehören. Unbelegte
 *    Punkte werden verworfen; bleibt keiner übrig, gilt die Antwort als unbelegt und die App
 *    zeigt die regelbasierte Notiz.
 */
import { list, text } from "./tasks-util";

export const GROUNDING_SYSTEM = [
  "Du bist ein sachlicher Ausdauer- und Ernährungscoach. Du FORMULIERST nur – entschieden haben feste Regeln.",
  "Verbindlich:",
  "- Verwende ausschließlich Fakten, Zahlen und Einheiten aus der Anfrage. Erfinde keine Werte, Paces, Wattzahlen, " +
    "Zeiten, Studien oder Quellen.",
  "- Begründungen nur mit den mitgeschickten belegten Regeln (Abschnitt „Belegte Regeln“). Wenn etwas dort nicht " +
    "steht, lass es weg statt zu spekulieren.",
  "- Keine Diagnosen, keine Medikamente, keine Nahrungsergänzung ohne Anlass in den Fakten.",
  "- Nie mehr Training oder zusätzliche Einheiten fordern; verpasste Einheiten nicht vorwerfen.",
  "- Lieber kurz und richtig als ausführlich.",
].join("\n");

export interface EvidenceItem {
  id: string;
  statement: string;
}

/** Belegte Regeln aus der App-Eingabe (`evidence: [{id, statement}]`). */
export function evidenceFrom(input: Record<string, unknown>): EvidenceItem[] {
  if (!Array.isArray(input.evidence)) return [];
  return input.evidence.slice(0, 20).flatMap((item) => {
    const record = (typeof item === "object" && item !== null ? item : {}) as Record<string, unknown>;
    const id = text(record.id, 60);
    const statement = text(record.statement, 400);
    return id && statement ? [{ id, statement }] : [];
  });
}

export function evidenceBlock(items: EvidenceItem[]): string {
  if (items.length === 0) return "";
  return ["Belegte Regeln (id: Aussage):", ...items.map((item) => `- ${item.id}: ${item.statement}`)].join(
    "\n",
  );
}

export const POINTS_WITH_SOURCES =
  'Antworte AUSSCHLIESSLICH mit JSON der Form {"punkte": ["...", "..."], "quellen": ["<id>", ...]}. ' +
  '"quellen" enthält nur ids aus „Belegte Regeln“, auf die sich deine Punkte stützen (oder eine leere Liste).';

export class GroundingError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "GroundingError";
  }
}

/** Zahlen eines Textes, normalisiert („4,8“ → „4.8“, „12,0“ → „12“). */
export function numbersIn(value: string): Set<string> {
  const result = new Set<string>();
  for (const match of value.matchAll(/\d+(?:[.,]\d+)?/g)) {
    const normalized = Number(match[0].replace(",", "."));
    if (Number.isFinite(normalized)) result.add(String(normalized));
  }
  return result;
}

const FREE_NUMBERS = new Set(["0", "1", "2", "3"]);

export interface GroundedPoints {
  punkte: string[];
  quellen: string[];
  verworfen: number;
}

/** Prüft `{"punkte": [...], "quellen": [...]}` gegen den Anfragetext und die erlaubten Quellen. */
export function groundPoints(output: unknown, promptText: string, allowedSources: string[]): GroundedPoints {
  const record = (typeof output === "object" && output !== null ? output : {}) as Record<string, unknown>;
  const raw = list(Array.isArray(record.punkte) ? record.punkte : output, 6, 600);
  const known = numbersIn(promptText);
  const punkte = raw.filter((point) =>
    [...numbersIn(point)].every((n) => known.has(n) || FREE_NUMBERS.has(n)),
  );
  if (punkte.length === 0) throw new GroundingError("KI-Antwort enthielt nur unbelegte Aussagen");
  const allowed = new Set(allowedSources);
  const quellen = [...new Set(list(record.quellen, 10, 60))].filter((id) => allowed.has(id));
  return { punkte, quellen, verworfen: raw.length - punkte.length };
}
