import { describe, expect, it } from "vitest";
import { generate } from "../src/ai";
import { compatBase } from "../src/openai-compat";
import { listPriceUsd, parsePreference, providerInfo, providerOrder } from "../src/providers";
import type { Env, GenerateRequest, WorkersAiBinding } from "../src/types";
import { env, fakeDeps, geminiText, groqText, jsonResponse } from "./helpers";

const request: GenerateRequest = { prompt: "Hallo", json: true, images: [] };

function workersAi(
  result: unknown | Error,
): WorkersAiBinding & { calls: { model: string; input: unknown }[] } {
  const calls: { model: string; input: unknown }[] = [];
  return {
    calls,
    run: async (model, input) => {
      calls.push({ model, input });
      if (result instanceof Error) throw result;
      return result;
    },
  };
}

const ids = (list: { id: string }[]) => list.map((provider) => provider.id);

describe("providerOrder", () => {
  it("standard, eigene Reihenfolge, Vorliebe", () => {
    expect(ids(providerOrder(env, "auto"))).toEqual(["gemini", "workers_ai", "groq", "openai_compat"]);
    expect(ids(providerOrder({ ...env, AI_PROVIDER_ORDER: "groq, workers_ai" }, "auto"))).toEqual([
      "groq",
      "workers_ai",
      "gemini",
      "openai_compat",
    ]);
    expect(ids(providerOrder(env, "gemini"))[0]).toBe("gemini");
  });

  it("privat schickt nichts an Anbieter, die mit Eingaben trainieren", () => {
    expect(ids(providerOrder(env, "privat"))).toEqual(["openai_compat", "workers_ai", "groq"]);
    expect(ids(providerOrder(env, "workers_ai"))).toEqual(["workers_ai", "groq", "openai_compat"]);
  });

  it("Bilder nur an Anbieter mit Bild-Eingabe", () => {
    expect(ids(providerOrder(env, "privat", true))).not.toContain("openai_compat");
  });

  it("unbekannte Vorliebe = auto", () => {
    expect(parsePreference("quatsch")).toBe("auto");
    expect(parsePreference("workers_ai")).toBe("workers_ai");
  });
});

describe("Workers AI", () => {
  it("antwortet im Chat-Format mit Verbrauch und ohne Denkmodus", async () => {
    const ai = workersAi({
      choices: [{ message: { content: '{"ok": true}' } }],
      usage: { prompt_tokens: 1000, completion_tokens: 200 },
    });
    const result = await generate(request, { ...env, AI: ai }, fakeDeps([]), "workers_ai");
    expect(result).toMatchObject({ provider: "workers_ai", text: '{"ok": true}' });
    expect(result.usage).toEqual({ inputTokens: 1000, outputTokens: 200 });
    expect(ai.calls[0]?.model).toBe("@cf/google/gemma-4-26b-a4b-it");
    expect(ai.calls[0]?.input).toMatchObject({
      response_format: { type: "json_object" },
      chat_template_kwargs: { enable_thinking: false },
    });
  });

  it("ältere Antwortform und Objekt im JSON-Modus", async () => {
    const ai = workersAi({ response: { ok: true } });
    const result = await generate(request, { ...env, AI: ai }, fakeDeps([]), "workers_ai");
    expect(result.text).toBe('{"ok":true}');
  });

  it("Kapazitätsfehler: weiter zum nächsten Anbieter", async () => {
    const ai = workersAi(new Error("3040: Capacity temporarily exceeded"));
    const deps = fakeDeps([() => groqText('{"ok": true}')]);
    const result = await generate(request, { ...env, AI: ai }, deps, "workers_ai");
    expect(result.provider).toBe("groq");
    expect(ai.calls.length).toBe(2);
  });

  it("ohne Binding wird übersprungen", async () => {
    const deps = fakeDeps([() => geminiText('{"ok": true}')]);
    const result = await generate(request, env, deps, "auto");
    expect(result.provider).toBe("gemini");
  });
});

describe("eigener Server", () => {
  const own: Env = {
    ...env,
    OPENAI_COMPAT_URL: "https://llm.example.org/v1/",
    OPENAI_COMPAT_MODEL: "qwen3:14b",
  };

  it("ruft die OpenAI-kompatible API auf", async () => {
    const deps = fakeDeps([
      () => jsonResponse(200, { choices: [{ message: { content: "{}" } }], usage: { prompt_tokens: 5 } }),
    ]);
    const result = await generate(request, { ...own, OPENAI_COMPAT_KEY: "k" }, deps, "privat");
    expect(result.provider).toBe("openai_compat");
    expect(deps.calls[0]?.url).toBe("https://llm.example.org/v1/chat/completions");
    expect(deps.calls[0]?.body).toMatchObject({ model: "qwen3:14b" });
    expect(result.usage).toEqual({ inputTokens: 5, outputTokens: 0 });
    expect(listPriceUsd("openai_compat", "qwen3:14b", result.usage)).toBe(0);
  });

  it("nur https", () => {
    expect(compatBase("http://192.168.0.2:11434/v1")).toBeUndefined();
    expect(compatBase("https://x.org/v1/chat/completions")).toBe("https://x.org/v1");
  });

  it("privat ohne passende Anbieter: klare Fehlermeldung, nichts an Gemini", async () => {
    const onlyGemini: Env = { GEMINI_API_KEY: "g", COACH_APP_TOKEN: "t" };
    const deps = fakeDeps([]);
    await expect(generate(request, onlyGemini, deps, "privat")).rejects.toThrow(/nicht eingerichtet/);
    expect(deps.calls.length).toBe(0);
  });
});

describe("Kosten und Übersicht", () => {
  it("Listenpreis aus Tokens", () => {
    expect(
      listPriceUsd("workers_ai", "@cf/google/gemma-4-26b-a4b-it", {
        inputTokens: 1_000_000,
        outputTokens: 0,
      }),
    ).toBe(0.1);
    expect(listPriceUsd("gemini", "x", undefined)).toBeUndefined();
  });

  it("Übersicht zeigt eingerichtete Anbieter", () => {
    const info = providerInfo({ ...env, AI: workersAi({}) }) as { id: string; enabled: boolean }[];
    expect(info.find((entry) => entry.id === "workers_ai")?.enabled).toBe(true);
    expect(info.find((entry) => entry.id === "openai_compat")?.enabled).toBe(false);
  });
});

describe("Antwort der App-Schnittstelle", () => {
  it("liefert Verbrauch und Listenpreis, Vorliebe aus der Anfrage", async () => {
    const { handle } = await import("../src/index");
    const deps = fakeDeps([
      () =>
        jsonResponse(200, {
          candidates: [
            { content: { parts: [{ text: '{"ok": true, "gruss": "Hallo"}' }] }, finishReason: "STOP" },
          ],
          usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 20, thoughtsTokenCount: 5 },
        }),
    ]);
    const response = await handle(
      new Request("https://w.example/v1/ai/generate", {
        method: "POST",
        headers: { authorization: `Bearer ${env.COACH_APP_TOKEN}` },
        body: JSON.stringify({ task: "ping", provider: "gemini" }),
      }),
      env,
      deps,
    );
    const body = (await response.json()) as { usage?: { inputTokens: number; outputTokens: number } };
    expect(response.status).toBe(200);
    expect(body.usage).toMatchObject({ inputTokens: 100, outputTokens: 25 });
  });
});
