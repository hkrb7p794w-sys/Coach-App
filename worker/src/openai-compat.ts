/**
 * Eigener oder weiterer Anbieter mit OpenAI-kompatibler API: lokal gehostet (Ollama, LM Studio, llama.cpp,
 * vLLM – von außen erreichbar z. B. über Cloudflare Tunnel) oder gehostet (OpenRouter, Mistral, DeepSeek …).
 * Adresse, Key und Modell kommen aus den Worker-Variablen; ohne Adresse ist der Anbieter aus.
 */
import { type ChatCompletion, chatUsage, messages } from "./groq";
import {
  attemptSignal,
  type Deps,
  type Env,
  type GenerateRequest,
  type GenerateResult,
  ProviderError,
} from "./types";

export function compatBase(url: string | undefined): string | undefined {
  const trimmed = url?.trim().replace(/\/+$/, "");
  if (!trimmed || !/^https:\/\//.test(trimmed)) return undefined;
  return trimmed.endsWith("/chat/completions") ? trimmed.slice(0, -"/chat/completions".length) : trimmed;
}

export async function generateWithOpenAiCompat(
  request: GenerateRequest,
  env: Env,
  deps: Deps,
): Promise<GenerateResult> {
  const base = compatBase(env.OPENAI_COMPAT_URL);
  const model = env.OPENAI_COMPAT_MODEL?.trim();
  if (!base || !model) throw new ProviderError("Eigener Server ist nicht eingerichtet", false);
  let response: Response;
  try {
    response = await deps.fetch(`${base}/chat/completions`, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(env.OPENAI_COMPAT_KEY ? { authorization: `Bearer ${env.OPENAI_COMPAT_KEY}` } : {}),
      },
      body: JSON.stringify({
        model,
        messages: messages(request),
        max_tokens: request.maxOutputTokens ?? 4096,
        temperature: request.temperature ?? 0.4,
        ...(request.json ? { response_format: { type: "json_object" } } : {}),
      }),
      signal: attemptSignal(request, deps),
    });
  } catch (error) {
    throw new ProviderError(`Eigener Server nicht erreichbar: ${String(error)}`, true);
  }
  const raw = await response.text();
  if (response.status === 429 || response.status >= 500) {
    throw new ProviderError(`Eigener Server HTTP ${response.status} (${model})`, true, response.status);
  }
  if (!response.ok) {
    throw new ProviderError(`Eigener Server HTTP ${response.status} (${model})`, false);
  }
  const body = JSON.parse(raw) as ChatCompletion;
  const text = body.choices?.[0]?.message?.content?.trim();
  if (!text) throw new ProviderError(`Eigener Server (${model}) hat leeren Text geliefert`, true);
  if (request.json && body.choices?.[0]?.finish_reason === "length") {
    throw new ProviderError(`Eigener Server (${model}): Antwort abgeschnitten`, false);
  }
  return { text, model, provider: "openai_compat", usage: chatUsage(body) };
}
