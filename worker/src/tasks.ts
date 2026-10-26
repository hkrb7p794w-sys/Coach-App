/**
 * Aufgaben (Prompts) liegen im Worker, nicht in der App: Prompt-Änderungen brauchen so nur einen
 * Worker-Deploy und keine neue App-Version. Die App schickt nur abgeleitete Werte (Datenschutzmodus
 * „reduziert“ entscheidet die App, bevor sie sendet).
 *
 * Regel aus dem Altbestand: Die Regeln entscheiden, die KI formuliert nur.
 */
import { mealPrompt, nutritionReviewPrompt } from "./nutrition";
import { athleteProfile } from "./profile";
import { list, text } from "./tasks-util";

export { list, text } from "./tasks-util";

export interface TaskDefinition {
  json: boolean;
  allowImages: boolean;
  build(input: Record<string, unknown>, images: number): { system?: string; prompt: string };
}

const GERMAN = "Schreibe durchgängig in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).";

function object(value: unknown): Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : {};
}

function km(value: unknown): string {
  return typeof value === "number" && Number.isFinite(value)
    ? `${value.toFixed(1).replace(".", ",")} km`
    : "–";
}

/** Tages-Coaching-Notiz (Portierung von `generate_coaching_note`, garmin_ai_coach/ai_coach.py). */
export function dailyNotePrompt(input: Record<string, unknown>): string {
  const decision = object(input.decision);
  const volumes = object(input.volumes);
  const today = list(input.todayItems).join(", ") || "nichts Festes";
  const open = list(input.openItems).join(", ") || "nichts";
  const daysLeft = typeof input.daysLeftInWeek === "number" ? input.daysLeftInWeek : undefined;
  const reasons = list(decision.reasons).join("; ");
  const decisionText = decision.label
    ? `${text(decision.label)} - ${text(decision.advice)} Gründe: ${reasons}.`
    : "keine";
  const vitals = list(input.vitals)
    .map((line) => `- ${line}`)
    .join("\n");

  return [
    "Du bist ein Ausdauersport-Coach für einen Age-Group-Athleten in der Vorbereitung auf die " +
      `${text(input.raceName)} am ${text(input.raceDate)}. Zielzeit: ${text(input.raceGoal)}.`,
    "",
    athleteProfile(text(input.testValues)),
    "",
    `Heute ist ${text(input.weekday)}. Trainingsphase: ${text(input.phase)} (Fokus: ${text(input.phaseFocus)}). ` +
      `Noch ${text(input.daysToRace)} Tage bis zum Rennen.`,
    `Plan dieser Phase: ${text(input.phaseDetail, 1500)}`,
    `Laut Wochenrahmen heute: ${today}. Diese Woche noch offen: ${open} ` +
      `(noch ${daysLeft ?? "?"} Tage in der Woche).`,
    ...(daysLeft === 0
      ? [
          "Heute ist der LETZTE Tag der Woche: Offenes kann nicht mehr nachgeholt werden - nichts auf spätere " +
            'Tage dieser Woche verschieben und nicht von einem "frischen Tag" sprechen; was bei der ' +
            "Tagesentscheidung nicht mehr geht, entfällt diese Woche.",
        ]
      : []),
    `Wochenvolumen bisher: Schwimmen ${km(volumes.swimKm)}, Rad ${km(volumes.bikeKm)}, Lauf ${km(volumes.runKm)}.`,
    "",
    "Erholung:",
    vitals || "- keine Daten",
    `VERBINDLICHE Tagesentscheidung (regelbasiert, nicht ändern): ${decisionText}`,
    "",
    "Aufgabe: Formuliere daraus eine kurze, konkrete Umsetzung für heute. Antworte " +
      'AUSSCHLIESSLICH mit JSON der Form {"punkte": ["...", "..."]} mit 2-3 Punkten, je ' +
      "ein Satz, ohne Aufzählungszeichen im Text:",
    "1. Was heute konkret trainiert wird (passend zu Wochentag, offener Woche und der " +
      "Tagesentscheidung - bei 'locker' eine entschärfte Variante, bei 'Ruhetag' nichts Hartes). " +
      "Einheiten mit dem Zusatz 'schon erledigt' nicht noch einmal verordnen.",
    "2. Ein Satz zur Einordnung der Erholung (keine Rohzahlen aufzählen).",
    "3. Optional: ein Hinweis, wie die offene Woche im bestehenden Rahmen noch sinnvoll " +
      "aufgeht - keine zusätzlichen Einheiten fordern.",
    GERMAN,
  ].join("\n");
}

export const TASKS: Record<string, TaskDefinition> = {
  /** Verbindungstest aus den App-Einstellungen. */
  ping: {
    json: true,
    allowImages: false,
    build: () => ({
      prompt: `Antworte ausschließlich mit JSON der Form {"ok": true, "gruss": "<ein kurzer Satz>"}. ${GERMAN}`,
    }),
  },
  /** Tagesnotiz zur regelbasierten Tagesampel. */
  daily_note: {
    json: true,
    allowImages: false,
    build: (input) => ({ prompt: dailyNotePrompt(input) }),
  },
  /** Mahlzeit per Foto und/oder Text in Positionen mit Nährwerten zerlegen. */
  meal_analyze: {
    json: true,
    allowImages: true,
    build: (input, images) => ({ prompt: mealPrompt(input, images > 0) }),
  },
  /** Ernährung und Training des Tages gemeinsam auswerten. */
  nutrition_review: {
    json: true,
    allowImages: false,
    build: (input) => ({ prompt: nutritionReviewPrompt(input) }),
  },
};

export function findTask(name: unknown): TaskDefinition | undefined {
  return typeof name === "string" && Object.hasOwn(TASKS, name) ? TASKS[name] : undefined;
}
