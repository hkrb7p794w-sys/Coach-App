/**
 * Anbieter-Register: Jeder KI-Anbieter ist ein Eintrag mit gleicher Schnittstelle. Neue Anbieter oder Modelle
 * kommen hier dazu, ohne Aufgaben, Prompts oder die App zu ändern. Die App wählt nur eine Vorliebe
 * (`auto`, `privat` oder einen Anbieter); welche Anbieter eingerichtet sind, entscheidet der Worker.
 */
import { generateWithGemini } from "./gemini";
import { generateWithGroq } from "./groq";
import { compatBase, generateWithOpenAiCompat } from "./openai-compat";
import type { Deps, Env, GenerateRequest, GenerateResult, ProviderId, Usage } from "./types";
import { DEFAULT_WORKERS_AI_MODEL, generateWithWorkersAi } from "./workers-ai";

export interface ProviderDefinition {
  id: ProviderId;
  label: string;
  enabled(env: Env): boolean;
  /** Modell, das ohne Ausweichen genutzt wird (für die Anzeige). */
  model(env: Env): string;
  /** Kostenlose Kontingente dürfen Eingaben zur Produktverbesserung nutzen (Gemini, „Unpaid Services“). */
  usesInputsForTraining: boolean;
  /** Bilder (Mahlzeit, Etikett) möglich. */
  vision: boolean;
  /** Listenpreis in US-Dollar je Million Tokens (Eingabe, Ausgabe) – Schätzung, falls bezahlt würde. */
  pricePerMillion(model: string): [number, number];
  run(request: GenerateRequest, env: Env, deps: Deps): Promise<GenerateResult>;
}

/** Listenpreise Workers AI (developers.cloudflare.com/workers-ai/platform/pricing, Stand 20.10.2026). */
const WORKERS_AI_PRICES: Record<string, [number, number]> = {
  "@cf/google/gemma-4-26b-a4b-it": [0.1, 0.3],
  "@cf/qwen/qwen3-30b-a3b-fp8": [0.051, 0.335],
  "@cf/qwen/qwen3.8-27b": [0.45, 3.2],
  "@cf/openai/gpt-oss-120b": [0.35, 0.75],
  "@cf/openai/gpt-oss-20b": [0.2, 0.3],
  "@cf/meta/llama-4-scout-17b-16e-instruct": [0.27, 0.85],
  "@cf/deepseek-ai/deepseek-v4.1-flash-1017": [0.3, 1.2],
};

export const PROVIDERS: ProviderDefinition[] = [
  {
    id: "gemini",
    label: "Google Gemini",
    enabled: (env) => Boolean(env.GEMINI_API_KEY),
    model: (env) => env.GEMINI_MODEL?.trim() || "gemini-3.6-flash",
    usesInputsForTraining: true,
    vision: true,
    // Im kostenlosen Kontingent 0 €; Listenpreis grob wie Gemini Flash.
    pricePerMillion: () => [0.3, 2.5],
    run: generateWithGemini,
  },
  {
    id: "workers_ai",
    label: "Cloudflare Workers AI",
    enabled: (env) => Boolean(env.AI),
    model: (env) => env.WORKERS_AI_MODEL?.trim() || DEFAULT_WORKERS_AI_MODEL,
    usesInputsForTraining: false,
    vision: true,
    pricePerMillion: (model) => WORKERS_AI_PRICES[model] ?? [0.3, 1],
    run: generateWithWorkersAi,
  },
  {
    id: "groq",
    label: "Groq",
    enabled: (env) => Boolean(env.GROQ_API_KEY),
    model: (env) => env.GROQ_MODEL?.trim() || "llama-3.3-70b-versatile",
    usesInputsForTraining: false,
    vision: true,
    pricePerMillion: () => [0.59, 0.79],
    run: generateWithGroq,
  },
  {
    id: "openai_compat",
    label: "Eigener Server",
    enabled: (env) => Boolean(compatBase(env.OPENAI_COMPAT_URL) && env.OPENAI_COMPAT_MODEL?.trim()),
    model: (env) => env.OPENAI_COMPAT_MODEL?.trim() || "",
    usesInputsForTraining: false,
    vision: false,
    // Lokal: keine Gebühr je Token (Strom und Hardware zählen extra).
    pricePerMillion: () => [0, 0],
    run: generateWithOpenAiCompat,
  },
];

export type Preference = "auto" | "privat" | ProviderId;

export function parsePreference(value: unknown): Preference {
  if (value === "privat" || value === "auto") return value;
  return PROVIDERS.some((provider) => provider.id === value) ? (value as ProviderId) : "auto";
}

/**
 * Reihenfolge der Versuche:
 * - `auto`: AI_PROVIDER_ORDER bzw. Standard (Gemini, Workers AI, Groq, eigener Server).
 * - `privat`: nur Anbieter, die Eingaben nicht zum Training nutzen (eigener Server zuerst).
 * - ein Anbieter: dieser zuerst, danach die übrigen wie bei `auto` (bzw. `privat`, wenn er privat ist).
 * Bilder nur an Anbieter mit Bild-Eingabe.
 */
export function providerOrder(env: Env, preference: Preference, hasImages = false): ProviderDefinition[] {
  const configured = (env.AI_PROVIDER_ORDER ?? "")
    .split(",")
    .map((id) => id.trim())
    .filter(Boolean);
  const byId = new Map(PROVIDERS.map((provider) => [provider.id, provider]));
  const base = configured.length
    ? [...configured.flatMap((id) => byId.get(id as ProviderId) ?? []), ...PROVIDERS]
    : PROVIDERS;
  let ordered = [...new Set(base)];
  const privateOnly =
    preference === "privat" ||
    (preference !== "auto" && byId.get(preference)?.usesInputsForTraining === false);
  if (preference === "privat") {
    ordered = [
      ...ordered.filter((provider) => provider.id === "openai_compat"),
      ...ordered.filter((provider) => provider.id !== "openai_compat"),
    ];
  } else if (preference !== "auto") {
    const first = byId.get(preference);
    if (first) ordered = [first, ...ordered.filter((provider) => provider !== first)];
  }
  if (privateOnly) ordered = ordered.filter((provider) => !provider.usesInputsForTraining);
  if (hasImages) ordered = ordered.filter((provider) => provider.vision);
  return ordered;
}

/** Geschätzter Listenpreis einer Anfrage in US-Dollar (0 bei lokalem Server). */
export function listPriceUsd(
  provider: ProviderId,
  model: string,
  usage: Usage | undefined,
): number | undefined {
  if (!usage) return undefined;
  const definition = PROVIDERS.find((entry) => entry.id === provider);
  if (!definition) return undefined;
  const [input, output] = definition.pricePerMillion(model);
  return Math.round(((usage.inputTokens * input + usage.outputTokens * output) / 1_000_000) * 1e6) / 1e6;
}

/** Übersicht für die App (Einstellungen): eingerichtete Anbieter mit Modell und Datenschutz-Eigenschaften. */
export function providerInfo(env: Env): unknown[] {
  return PROVIDERS.map((provider) => ({
    id: provider.id,
    label: provider.label,
    enabled: provider.enabled(env),
    model: provider.enabled(env) ? provider.model(env) : null,
    usesInputsForTraining: provider.usesInputsForTraining,
    vision: provider.vision,
  }));
}
