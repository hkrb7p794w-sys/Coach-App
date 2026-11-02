export interface Env {
  /** Secrets (per Deploy-Workflow aus GitHub-Secrets gesetzt). */
  GEMINI_API_KEY?: string;
  GROQ_API_KEY?: string;
  COACH_APP_TOKEN?: string;
  /** Gesperrte Gast-IDs (siehe auth.ts), durch Komma getrennt. */
  REVOKED_GUESTS?: string;
  /** Workers KV „coach-releases“: IPA und Versionsangaben für die private SideStore-Quelle. */
  RELEASES?: KVNamespace;
  /** Workers KV „coach-league“: Ranglisten (nur Namen und Punkte). */
  LEAGUE?: KVNamespace;
  /** Variablen aus wrangler.jsonc. */
  GEMINI_MODEL?: string;
  GEMINI_FALLBACK_MODEL?: string;
  GROQ_MODEL?: string;
  GROQ_VISION_MODEL?: string;
  /** Workers AI (Binding „AI“ in wrangler.jsonc): offene Modelle bei Cloudflare, kein eigener Key nötig. */
  AI?: WorkersAiBinding;
  WORKERS_AI_MODEL?: string;
  /** Eigener OpenAI-kompatibler Server (z. B. Ollama/LM Studio per Tunnel, OpenRouter, Mistral). */
  OPENAI_COMPAT_URL?: string;
  OPENAI_COMPAT_KEY?: string;
  OPENAI_COMPAT_MODEL?: string;
  /** Reihenfolge der Anbieter bei „Automatisch“, z. B. "gemini,workers_ai,groq". */
  AI_PROVIDER_ORDER?: string;
}

/** Ausschnitt des Workers-AI-Bindings, den der Worker nutzt (Tests ersetzen ihn). */
export interface WorkersAiBinding {
  run(model: string, input: unknown, options?: unknown): Promise<unknown>;
}

export interface ImageInput {
  mimeType: string;
  /** Base64 ohne `data:`-Präfix. */
  data: string;
}

export interface GenerateRequest {
  system?: string;
  prompt: string;
  json: boolean;
  images: ImageInput[];
  temperature?: number;
  /** Längere Antworten (z. B. Wochenrezepte); Standard 4096. */
  maxOutputTokens?: number;
}

export type ProviderId = "gemini" | "groq" | "workers_ai" | "openai_compat";

/** Verbrauch einer Anfrage, so wie der Anbieter ihn meldet (fehlt, wenn er nichts meldet). */
export interface Usage {
  inputTokens: number;
  outputTokens: number;
}

export interface GenerateResult {
  text: string;
  model: string;
  provider: ProviderId;
  usage?: Usage;
}

/** Abhängigkeiten, die Tests ersetzen. */
export interface Deps {
  fetch: typeof fetch;
  sleep: (ms: number) => Promise<void>;
  now: () => number;
  log: (message: string) => void;
}

export const defaultDeps: Deps = {
  fetch: (input, init) => fetch(input, init),
  sleep: (ms) => new Promise((resolve) => setTimeout(resolve, ms)),
  now: () => Date.now(),
  log: (message) => console.log(message),
};

export class ProviderError extends Error {
  constructor(
    message: string,
    /** true: ein anderes Modell oder ein späterer Versuch kann helfen. */
    readonly retryable: boolean,
    readonly status?: number,
  ) {
    super(message);
    this.name = "ProviderError";
  }
}
