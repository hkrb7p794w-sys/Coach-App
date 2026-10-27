/**
 * Chat mit dem Coach: Die App schickt die Frage, die letzten Nachrichten und eine Liste fester Fakten aus ihren
 * Regeln (Tagesampel, Plan, Ziele, Schlaf, Ernährung). Die KI antwortet nur aus diesen Fakten; Zahlen, die nicht
 * in der Anfrage stehen, führen zum Verwerfen der Antwort.
 */
import { evidenceBlock, evidenceFrom, GROUNDING_SYSTEM, GroundingError, numbersIn } from "./grounding";
import { list, text } from "./tasks-util";

export const CHAT_SYSTEM = [
  GROUNDING_SYSTEM,
  "Zusätzlich für den Chat:",
  "- Beantworte nur Fragen zu Training, Erholung, Schlaf, Ernährung und zur App. Bei anderen Themen sag freundlich, " +
    "wobei du helfen kannst.",
  "- Steht die Antwort nicht in den Fakten, sag das offen und nenne, wo in der App man nachsehen kann.",
  "- Bei Schmerzen, Brustdruck, Schwindel, Ohnmacht, Verletzungen oder Essstörungen: keine Ferndiagnose, sondern zu " +
    "ärztlicher Abklärung raten und Training bis dahin ruhen lassen.",
  "- Höchstens etwa 120 Wörter, du-Form, ohne Markdown-Überschriften.",
].join("\n");

const FREE_NUMBERS = new Set(["0", "1", "2", "3"]);

export function chatPrompt(input: Record<string, unknown>): string {
  const history = Array.isArray(input.history) ? input.history.slice(-6) : [];
  const lines = history.flatMap((entry) => {
    const record = (typeof entry === "object" && entry !== null ? entry : {}) as Record<string, unknown>;
    const said = text(record.text, 600);
    if (!said) return [];
    return [`${record.role === "coach" ? "Coach" : "Person"}: ${said}`];
  });
  return [
    "Fakten aus der App (von festen Regeln berechnet):",
    ...list(input.facts, 40, 300).map((line) => `- ${line}`),
    "",
    evidenceBlock(evidenceFrom(input)),
    "",
    ...(lines.length ? ["Bisheriger Verlauf:", ...lines, ""] : []),
    `Frage: ${text(input.question, 600) || "(leer)"}`,
    "",
    'Antworte AUSSCHLIESSLICH mit JSON der Form {"antwort": "...", "quellen": ["<id>", ...]}. "quellen" enthält ' +
      "nur ids aus „Belegte Regeln“, auf die sich die Antwort stützt (oder eine leere Liste). Schreibe durchgängig " +
      "in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).",
  ].join("\n");
}

/** Prüft die Antwort: nur bekannte Zahlen, nur mitgeschickte Quellen. */
export function groundChat(output: unknown, requestText: string, input: Record<string, unknown>): unknown {
  const record = (typeof output === "object" && output !== null ? output : {}) as Record<string, unknown>;
  const antwort = text(record.antwort, 1500);
  if (!antwort) throw new GroundingError("Leere Chat-Antwort");
  const known = numbersIn(requestText);
  const unknown = [...numbersIn(antwort)].filter((n) => !known.has(n) && !FREE_NUMBERS.has(n));
  if (unknown.length > 0)
    throw new GroundingError(`Chat-Antwort mit unbelegten Zahlen: ${unknown.join(", ")}`);
  const allowed = new Set(evidenceFrom(input).map((item) => item.id));
  const quellen = [...new Set(list(record.quellen, 10, 60))].filter((id) => allowed.has(id));
  return { antwort, quellen };
}
