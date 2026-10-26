import { describe, expect, it } from "vitest";
import { GroundingError } from "../src/grounding";
import { gymHintsPrompt } from "../src/gym";
import { findTask } from "../src/tasks";

const input = {
  goal: "Muskeln aufbauen",
  recovery: "gut",
  exercises: [
    "Bankdrücken: zuletzt 60 kg × 10/10/10 Wdh., Ziel 6–10 → Erhöhen auf 62,5 kg (+4,2 %). alle Sätze am Ziel.",
    "Kniebeuge: zuletzt 80 kg × 7/6 Wdh., Ziel 6–10 → Bei 80 kg bleiben. noch 4 Wdh. bis zur Obergrenze.",
  ],
  volume: ["Brust: 6 Sätze in 7 Tagen", "Beine: 3 Sätze in 7 Tagen"],
  evidence: [{ id: "gym.progression", statement: "Doppelprogression." }],
};

describe("gym_hints", () => {
  it("übernimmt die Entscheidungen der Regeln in den Prompt", () => {
    const prompt = gymHintsPrompt(input);
    expect(prompt).toContain("- Bankdrücken: zuletzt 60 kg × 10/10/10 Wdh.");
    expect(prompt).toContain("Ziel: Muskeln aufbauen. Erholung heute: gut.");
    expect(prompt).toContain("- Beine: 3 Sätze in 7 Tagen");
    expect(prompt).toContain("- gym.progression: Doppelprogression.");
  });

  it("verträgt fehlende Werte", () => {
    expect(gymHintsPrompt({})).toContain("- keine Übungen mit Verlauf");
  });

  it("verwirft Hinweise mit erfundenen Gewichten", () => {
    const task = findTask("gym_hints");
    expect(task).toMatchObject({ json: true, allowImages: false });
    const prompt = gymHintsPrompt(input);
    const grounded = task?.ground?.(
      {
        punkte: [
          "Bankdrücken: Gehe auf 62,5 kg und starte wieder bei 6 Wdh.",
          "Kniebeuge auf 90 kg erhöhen.",
        ],
        quellen: ["gym.progression", "erfunden"],
      },
      prompt,
      input,
    ) as { punkte: string[]; quellen: string[] };
    expect(grounded.punkte).toEqual(["Bankdrücken: Gehe auf 62,5 kg und starte wieder bei 6 Wdh."]);
    expect(grounded.quellen).toEqual(["gym.progression"]);
    expect(() => task?.ground?.({ punkte: ["Nimm 100 kg."], quellen: [] }, prompt, input)).toThrow(
      GroundingError,
    );
  });
});
