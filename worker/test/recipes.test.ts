import { describe, expect, it } from "vitest";
import { handle } from "../src/index";
import { checkRecipes, weeklyRecipesPrompt } from "../src/recipes";
import { env, fakeDeps, jsonResponse } from "./helpers";

const input = {
  days: [
    {
      datum: "2026-11-02",
      wochentag: "Montag",
      training: "Lockerer Lauf",
      tagestyp: "Moderater Trainingstag",
      kcal: 2100,
      protein_g: 120,
      kohlenhydrate_g: 260,
      fett_g: 65,
    },
    { datum: "2026-11-03", wochentag: "Dienstag", training: "frei", tagestyp: "Ruhetag", kcal: 1800 },
  ],
  diet: "vegetarisch",
  goal: "Abnehmen",
  allergens: ["Erdnüsse"],
  dislikes: "keine Pilze",
  maxMinutes: 20,
  snacks: false,
  mealPrep: true,
  gaps: ["Ballaststoffe: im Schnitt 18 von 30 g (60 %)"],
  favorites: ["Skyr", "Haferflocken"],
};

describe("weekly_recipes", () => {
  it("übernimmt Ziele, Ernährungsweise und Wünsche", () => {
    const prompt = weeklyRecipesPrompt(input);
    expect(prompt).toContain("Vegetarisch: kein Fleisch");
    expect(prompt).toContain("strikt meiden, auch in Spuren als Zutat): Erdnüsse.");
    expect(prompt).toContain("Mag nicht: keine Pilze.");
    expect(prompt).toContain("höchstens 20 Minuten");
    expect(prompt).toContain("Frühstück, Mittagessen, Abendessen.");
    expect(prompt).toContain("Meal-Prep");
    expect(prompt).toContain(
      "- 2026-11-02 (Montag): Training Lockerer Lauf; Moderater Trainingstag; Ziel 2100 kcal",
    );
    expect(prompt).toContain("Ziel 1800 kcal, – g Protein");
    expect(prompt).toContain("Lücken der letzten Tage");
    expect(prompt).toContain("Skyr, Haferflocken");
  });

  it("behält nur angefragte Tage", () => {
    const checked = checkRecipes(
      {
        tage: [
          { datum: "2026-11-02", gerichte: [{ titel: "A" }] },
          { datum: "2030-01-01", gerichte: [] },
        ],
      },
      "",
      input,
    ) as { tage: { datum: string }[] };
    expect(checked.tage.map((day) => day.datum)).toEqual(["2026-11-02"]);
    expect(() => checkRecipes({ tage: [] }, "", input)).toThrow("keine passenden Tage");
  });

  it("nutzt mehr Ausgabe-Tokens", async () => {
    const deps = fakeDeps([
      () =>
        jsonResponse(200, {
          candidates: [
            {
              content: {
                parts: [{ text: JSON.stringify({ tage: [{ datum: "2026-11-02", gerichte: [] }] }) }],
              },
            },
          ],
        }),
    ]);
    const response = await handle(
      new Request("https://x/v1/ai/generate", {
        method: "POST",
        headers: { authorization: `Bearer ${env.COACH_APP_TOKEN}` },
        body: JSON.stringify({ task: "weekly_recipes", input }),
      }),
      env,
      deps,
    );
    expect(response.status).toBe(200);
    const body = deps.calls[0]?.body as { generationConfig: { maxOutputTokens: number } };
    expect(body.generationConfig.maxOutputTokens).toBe(16000);
  });
});
