/**
 * Hinweise zur Gewichtssteigerung im Krafttraining. Die Regeln der App (Doppelprogression mit Wiederholungen in
 * Reserve) haben je Übung entschieden; die KI fasst das in kurze, motivierende Hinweise für die nächste Einheit.
 */
import { evidenceBlock, evidenceFrom, POINTS_WITH_SOURCES } from "./grounding";
import { list, text } from "./tasks-util";

export function gymHintsPrompt(input: Record<string, unknown>): string {
  const exercises = list(input.exercises, 10, 500);
  return [
    "Du bist Krafttrainer. Die App hat je Übung mit festen Regeln entschieden, ob das Gewicht steigt, " +
      "gleich bleibt oder sinkt. Diese Entscheidungen übernimmst du unverändert.",
    `Ziel: ${text(input.goal, 80) || "nicht angegeben"}. Erholung heute: ${text(input.recovery, 120)}.`,
    "",
    "Übungen mit Entscheidung der Regeln:",
    ...(exercises.length ? exercises.map((line) => `- ${line}`) : ["- keine Übungen mit Verlauf"]),
    "",
    "Sätze je Muskel (7 Tage):",
    ...list(input.volume, 10, 80).map((line) => `- ${line}`),
    "",
    evidenceBlock(evidenceFrom(input)),
    "",
    `Aufgabe: ${POINTS_WITH_SOURCES} 2-4 Punkte, je ein bis zwei Sätze:`,
    "1. Für die Übungen mit „Erhöhen“: nenne Übung und neues Gewicht genau wie in den Fakten und einen " +
      "Technik- oder Ausführungstipp für die Steigerung (z. B. erst bei der Untergrenze beginnen).",
    "2. Für „Gewicht halten oder senken“ bzw. „Wiedereinstieg“: kurz, warum, ohne Vorwurf.",
    "3. Optional: ein Hinweis zur Nähe am Muskelversagen (Wiederholungen in Reserve) oder zu einem Muskel mit " +
      "wenig Sätzen – nur wenn es aus den Fakten hervorgeht.",
    "Nenne keine Gewichte, Prozente oder Wiederholungen, die nicht in den Fakten stehen. Keine zusätzlichen Sätze " +
      "oder Einheiten fordern. Schreibe durchgängig in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).",
  ].join("\n");
}
