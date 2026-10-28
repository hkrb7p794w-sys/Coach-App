import { describe, expect, it } from "vitest";
import { handle } from "../src/index";
import { GROUPS, labelPrompt, mealPrompt, nutritionReviewPrompt } from "../src/nutrition";
import { findTask } from "../src/tasks";
import { env, fakeDeps, geminiText } from "./helpers";

describe("meal_analyze", () => {
  it("baut den Prompt mit Ernährungsweise, eigenen Lebensmitteln und Foto-Regeln", () => {
    const prompt = mealPrompt(
      { text: "2 Eier und Kaffee", diet: "pescetarisch", personalFoods: ["Skyr"] },
      true,
    );
    expect(prompt).toContain("Mahlzeit: 2 Eier und Kaffee");
    expect(prompt).toContain("vegetarische Variante annehmen");
    expect(prompt).toContain("Skyr");
    expect(prompt).toContain("Foto: Schätze Mengen über Bezugsgrößen");
    expect(prompt).toContain(GROUPS.join(", "));
  });

  it("nutzt ohne Text das Foto und ohne Foto keine Foto-Regeln", () => {
    expect(mealPrompt({}, true)).toContain("Mahlzeit: (siehe Foto)");
    expect(mealPrompt({ text: "Apfel", diet: "alles" }, false)).not.toContain("Bezugsgrößen");
  });

  it("nimmt Bilder an und reicht sie an Gemini weiter", async () => {
    expect(findTask("meal_analyze")?.allowImages).toBe(true);
    const deps = fakeDeps([() => geminiText('{"titel": "Apfel", "items": []}')]);
    const request = new Request("https://x/v1/ai/generate", {
      method: "POST",
      headers: { authorization: "Bearer app-token-123" },
      body: JSON.stringify({
        task: "meal_analyze",
        input: { text: "" },
        images: [{ mimeType: "image/jpeg", data: "QUJD" }],
      }),
    });
    const response = await handle(request, env, deps);
    expect(response.status).toBe(200);
    expect(JSON.stringify(deps.calls[0]?.body)).toContain(
      '"inlineData":{"mimeType":"image/jpeg","data":"QUJD"}',
    );
  });
});

describe("nutrition_review", () => {
  it("fasst Ziele, Training und Mahlzeiten zusammen", () => {
    const prompt = nutritionReviewPrompt({
      weekday: "Samstag",
      time: "13:30",
      dayType: "Harter Trainingstag",
      dayTypeSource: "Garmin",
      phase: "Grundlage",
      training: ["Zwift 90 min, Last 140"],
      planned: ["Zwift-Einheit (Sa oder So)"],
      recovery: "Normal trainieren",
      goal: "Gewicht halten",
      diet: "Pescetarisch",
      mealCount: 2,
      meals: ["Frühstück: Haferflocken mit Milch"],
      nutrients: [
        { label: "Kohlenhydrate", unit: "g", actual: 180.4, target: 640 },
        { label: "davon Zucker", unit: "g", actual: 40, target: 80, upperLimit: true },
      ],
    });
    expect(prompt).toContain("Tagestyp für die Ernährung: Harter Trainingstag (Garmin)");
    expect(prompt).toContain("- Kohlenhydrate: 180 g von 640 g");
    expect(prompt).toContain("- davon Zucker: 40 g von 80 g (Obergrenze)");
    expect(prompt).toContain("Training heute: Zwift 90 min, Last 140.");
    expect(prompt).toContain('{"punkte"');
  });

  it("verträgt leere Eingaben", () => {
    const prompt = nutritionReviewPrompt({});
    expect(prompt).toContain("noch nichts aufgezeichnet");
    expect(prompt).toContain("- keine Daten");
  });
});

describe("nutrition_label", () => {
  it("liest nur ab und nimmt Bilder an", () => {
    expect(findTask("nutrition_label")?.allowImages).toBe(true);
    expect(findTask("nutrition_label")?.temperature).toBe(0);
    const prompt = labelPrompt();
    expect(prompt).toContain("Nichts schätzen");
    expect(prompt).toContain("portion_g");
  });
});
