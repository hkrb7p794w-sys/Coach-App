import { type Preference, providerOrder } from "./providers";
import type { Deps, Env, GenerateRequest, GenerateResult } from "./types";

export class AllProvidersFailed extends Error {
  constructor(readonly attempts: string[]) {
    super(`Alle KI-Anbieter fehlgeschlagen: ${attempts.join(" | ")}`);
    this.name = "AllProvidersFailed";
  }
}

/** Anbieter der Reihe nach (siehe providers.ts), bis einer antwortet. */
export async function generate(
  request: GenerateRequest,
  env: Env,
  deps: Deps,
  preference: Preference = "auto",
): Promise<GenerateResult> {
  const attempts: string[] = [];
  const providers = providerOrder(env, preference, request.images.length > 0);
  for (const provider of providers) {
    if (!provider.enabled(env)) {
      attempts.push(`${provider.label}: nicht eingerichtet`);
      continue;
    }
    try {
      return await provider.run(request, env, deps);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      deps.log(`[ai] ${provider.label} fehlgeschlagen: ${message}`);
      attempts.push(`${provider.label}: ${message}`);
    }
  }
  if (providers.length === 0) attempts.push("kein passender Anbieter für diese Einstellung");
  throw new AllProvidersFailed(attempts);
}

/** JSON aus einer Modellantwort, auch wenn sie in ```json … ``` eingepackt ist. */
export function parseJsonOutput(text: string): unknown {
  const fenced = text.match(/```(?:json)?\s*([\s\S]*?)```/);
  const body = (fenced?.[1] ?? text).trim();
  try {
    return JSON.parse(body);
  } catch (error) {
    // Manche Modelle liefern mehrere Objekte hintereinander („{…}\n{…}“), z. B. je Mahlzeit eines.
    const values = topLevelValues(body);
    if (values.length > 1) return values.map((value) => JSON.parse(value));
    throw error;
  }
}

/** Zerlegt Text in die obersten JSON-Objekte bzw. -Listen (Klammern außerhalb von Zeichenketten zählen). */
function topLevelValues(text: string): string[] {
  const values: string[] = [];
  let depth = 0;
  let start = -1;
  let inString = false;
  let escaped = false;
  for (let i = 0; i < text.length; i++) {
    const char = text[i];
    if (inString) {
      if (escaped) escaped = false;
      else if (char === "\\") escaped = true;
      else if (char === '"') inString = false;
      continue;
    }
    if (char === '"') inString = true;
    else if (char === "{" || char === "[") {
      if (depth === 0) start = i;
      depth++;
    } else if ((char === "}" || char === "]") && depth > 0) {
      depth--;
      if (depth === 0 && start >= 0) values.push(text.slice(start, i + 1));
    }
  }
  return depth === 0 ? values : [];
}
