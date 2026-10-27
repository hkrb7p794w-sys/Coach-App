import { describe, expect, it } from "vitest";
import { CHAT_SYSTEM, chatPrompt } from "../src/chat";
import { GroundingError } from "../src/grounding";
import { findTask } from "../src/tasks";

const input = {
  question: "Soll ich heute hart laufen?",
  history: [
    { role: "user", text: "Wie war mein Schlaf?" },
    { role: "coach", text: "Im Schnitt 6,4 Stunden." },
  ],
  facts: ["Tagesampel: locker (HRV unter dem Normalbereich)", "Geplant heute: Qualitätslauf, 45 min"],
  evidence: [{ id: "recovery.hrv", statement: "HRV im Wochenmittel." }],
};

describe("coach_chat", () => {
  it("baut Fakten, Verlauf und Frage in den Prompt", () => {
    const prompt = chatPrompt(input);
    expect(prompt).toContain("- Tagesampel: locker (HRV unter dem Normalbereich)");
    expect(prompt).toContain("Person: Wie war mein Schlaf?");
    expect(prompt).toContain("Coach: Im Schnitt 6,4 Stunden.");
    expect(prompt).toContain("Frage: Soll ich heute hart laufen?");
    expect(prompt).toContain("- recovery.hrv: HRV im Wochenmittel.");
    expect(CHAT_SYSTEM).toContain("ärztlicher Abklärung");
  });

  it("lässt belegte Antworten durch und filtert Quellen", () => {
    const task = findTask("coach_chat");
    const prompt = `${CHAT_SYSTEM}\n${chatPrompt(input)}`;
    const result = task?.ground?.(
      {
        antwort: "Heute lieber locker: 45 min ruhig statt Intervallen.",
        quellen: ["recovery.hrv", "erfunden"],
      },
      prompt,
      input,
    );
    expect(result).toEqual({
      antwort: "Heute lieber locker: 45 min ruhig statt Intervallen.",
      quellen: ["recovery.hrv"],
    });
  });

  it("verwirft Antworten mit erfundenen Zahlen oder ohne Text", () => {
    const task = findTask("coach_chat");
    const prompt = chatPrompt(input);
    expect(() => task?.ground?.({ antwort: "Lauf 12 km in 5:10 /km.", quellen: [] }, prompt, input)).toThrow(
      GroundingError,
    );
    expect(() => task?.ground?.({ antwort: "" }, prompt, input)).toThrow(GroundingError);
  });
});
