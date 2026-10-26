/**
 * Rezeptideen für die kommende Woche. Die App schickt je Tag Ziele aus ihren Regeln (Energie, Protein,
 * Kohlenhydrate je Trainingstag), Ernährungsweise, Allergene und Lücken der letzten Wochen. Die KI schlägt Gerichte
 * vor; die App prüft Ernährungsweise und Allergene erneut und passt die Mengen ans Tagesziel an.
 */
import { evidenceBlock, evidenceFrom, GroundingError } from "./grounding";
import { list, text } from "./tasks-util";

const DIET_TEXT: Record<string, string> = {
  alles: "Mischkost (alles erlaubt).",
  pescetarisch: "Pescetarisch: kein Fleisch und keine Wurst, Fisch und Meeresfrüchte erlaubt.",
  vegetarisch: "Vegetarisch: kein Fleisch, keine Wurst, kein Fisch, keine Meeresfrüchte.",
  vegan: "Vegan: keine tierischen Produkte (kein Fleisch, Fisch, Ei, Milchprodukte, Honig).",
};

const SHAPE = `Antwortformat (JSON):
{"tage": [{"datum": "JJJJ-MM-TT", "gerichte": [{"mahlzeit": "fruehstueck|mittagessen|abendessen|snack",
"titel": str, "minuten": number, "zubereitung": [str, ...],
"zutaten": [{"name": str, "menge_g": number, "menge_text": str,
"naehrwerte_100g": {"kcal": number, "protein_g": number, "carbs_g": number, "fat_g": number, "fiber_g": number}}]}]}]}`;

function dayLine(value: unknown): string {
  const day = (typeof value === "object" && value !== null ? value : {}) as Record<string, unknown>;
  const n = (key: string) => (typeof day[key] === "number" ? Math.round(day[key] as number) : "–");
  return (
    `- ${text(day.datum, 10)} (${text(day.wochentag, 12)}): Training ${text(day.training, 120)}; ` +
    `${text(day.tagestyp, 40)}; Ziel ${n("kcal")} kcal, ${n("protein_g")} g Protein, ` +
    `${n("kohlenhydrate_g")} g Kohlenhydrate, ${n("fett_g")} g Fett`
  );
}

export function weeklyRecipesPrompt(input: Record<string, unknown>): string {
  const days = Array.isArray(input.days) ? input.days.slice(0, 7) : [];
  const allergens = list(input.allergens, 10, 40);
  const gaps = list(input.gaps, 8, 120);
  const favorites = list(input.favorites, 15, 60);
  const minutes = typeof input.maxMinutes === "number" ? Math.round(input.maxMinutes) : 30;
  const meals =
    input.snacks === false
      ? "Frühstück, Mittagessen, Abendessen"
      : "Frühstück, Mittagessen, Abendessen, Snack";
  return [
    "Du bist Sporternährungs-Coach und Koch. Erstelle alltagstaugliche Rezeptideen für die kommende Woche.",
    `Ernährungsweise: ${DIET_TEXT[text(input.diet, 20)] ?? "Mischkost."}`,
    `Ziel: ${text(input.goal, 80) || "Gewicht halten"}.`,
    `Allergene/Unverträglichkeiten (strikt meiden, auch in Spuren als Zutat): ${allergens.join(", ") || "keine"}.`,
    `Mag nicht: ${text(input.dislikes, 200) || "nichts angegeben"}.`,
    `Zubereitung höchstens ${minutes} Minuten pro Gericht. Mahlzeiten pro Tag: ${meals}.`,
    input.mealPrep === true
      ? "Meal-Prep: Das Abendessen darf als Mittagessen am Folgetag wiederverwendet werden (gleiches Gericht)."
      : "",
    favorites.length ? `Isst gern bzw. oft (gern einbauen): ${favorites.join(", ")}.` : "",
    gaps.length ? `Lücken der letzten Tage (gezielt ausgleichen): ${gaps.join("; ")}.` : "",
    "",
    "Tagesziele (fest von der App berechnet, nicht ändern):",
    ...(days.length ? days.map(dayLine) : ["- keine Tage"]),
    "",
    evidenceBlock(evidenceFrom(input)),
    "",
    "Regeln:",
    "- Die Gerichte eines Tages zusammen sollen das Energie- und Proteinziel des Tages etwa treffen (±10 %).",
    "- Protein auf die Mahlzeiten verteilen (je Hauptmahlzeit eine gute Proteinquelle).",
    "- An Trainingstagen mit „Harter“ oder „Sehr harter Trainingstag“ mehr Kohlenhydrate (Reis, Nudeln, " +
      "Kartoffeln, Haferflocken, Obst); an Ruhetagen mehr Gemüse.",
    "- Saisonal, abwechslungsreich, mit Zutaten aus dem deutschen Supermarkt; Zutaten über die Woche wiederverwenden, " +
      "damit wenig übrig bleibt.",
    "- menge_g: Menge für eine Person in Gramm (roh, wie eingekauft; Flüssigkeiten in ml = g).",
    "- naehrwerte_100g: deine beste Schätzung je 100 g der Zutat so wie angegeben.",
    "- zubereitung: 2–6 kurze Schritte. titel: max. 40 Zeichen.",
    "- Keine Nahrungsergänzungsmittel, außer der Nutzer nennt sie als Lieblingslebensmittel.",
    `Antworte ausschließlich mit JSON. ${SHAPE}`,
    "Schreibe durchgängig in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).",
  ]
    .filter((line) => line !== "")
    .join("\n");
}

/** Form prüfen: nur Tage aus der Anfrage, Listen begrenzt. Inhaltliche Prüfung macht die App. */
export function checkRecipes(output: unknown, _request: string, input: Record<string, unknown>): unknown {
  const record = (typeof output === "object" && output !== null ? output : {}) as Record<string, unknown>;
  const wanted = new Set(
    (Array.isArray(input.days) ? input.days : []).map((day) =>
      text((day as Record<string, unknown> | null)?.datum, 10),
    ),
  );
  const tage = (Array.isArray(record.tage) ? record.tage : [])
    .filter((day) => wanted.has(text((day as Record<string, unknown> | null)?.datum, 10)))
    .slice(0, 7)
    .map((day) => {
      const value = day as Record<string, unknown>;
      const gerichte = (Array.isArray(value.gerichte) ? value.gerichte : []).slice(0, 6);
      return { datum: value.datum, gerichte };
    });
  if (tage.length === 0) throw new GroundingError("KI-Antwort enthielt keine passenden Tage");
  return { tage };
}
