export interface Env {
  /** Secrets (per Deploy-Workflow aus GitHub-Secrets gesetzt). */
  GEMINI_API_KEY?: string;
  GROQ_API_KEY?: string;
  COACH_APP_TOKEN?: string;
  /** Workers KV „coach-releases“: IPA und Versionsangaben für die private SideStore-Quelle. */
  RELEASES?: KVNamespace;
  /** Variablen aus wrangler.jsonc. */
  GEMINI_MODEL?: string;
  GEMINI_FALLBACK_MODEL?: string;
  GROQ_MODEL?: string;
  GROQ_VISION_MODEL?: string;
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
}

export interface GenerateResult {
  text: string;
  model: string;
  provider: "gemini" | "groq";
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
