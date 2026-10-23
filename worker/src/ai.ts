import { generateWithGemini } from "./gemini";
import { generateWithGroq } from "./groq";
import type { Deps, Env, GenerateRequest, GenerateResult } from "./types";

export class AllProvidersFailed extends Error {
  constructor(readonly attempts: string[]) {
    super(`Alle KI-Anbieter fehlgeschlagen: ${attempts.join(" | ")}`);
    this.name = "AllProvidersFailed";
  }
}

/** Gemini (inkl. Ausweichmodelle), danach Groq. */
export async function generate(request: GenerateRequest, env: Env, deps: Deps): Promise<GenerateResult> {
  const attempts: string[] = [];
  const providers = [
    { name: "Gemini", enabled: Boolean(env.GEMINI_API_KEY), run: generateWithGemini },
    { name: "Groq", enabled: Boolean(env.GROQ_API_KEY), run: generateWithGroq },
  ];
  for (const provider of providers) {
    if (!provider.enabled) {
      attempts.push(`${provider.name}: kein Key`);
      continue;
    }
    try {
      return await provider.run(request, env, deps);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      deps.log(`[ai] ${provider.name} fehlgeschlagen: ${message}`);
      attempts.push(`${provider.name}: ${message}`);
    }
  }
  throw new AllProvidersFailed(attempts);
}

/** JSON aus einer Modellantwort, auch wenn sie in ```json … ``` eingepackt ist. */
export function parseJsonOutput(text: string): unknown {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  return JSON.parse((fenced?.[1] ?? text).trim());
}
