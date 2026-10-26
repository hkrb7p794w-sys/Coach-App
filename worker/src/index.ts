/**
 * Cloudflare Worker „coach-ai“: nimmt Aufgaben der Coach-App entgegen und reicht sie an Gemini bzw.
 * Groq weiter. Die KI-Keys liegen nur hier (Worker-Secrets), nie in der App.
 *
 * GET  /v1/health        – ohne Anmeldung, zeigt Version und welche Anbieter konfiguriert sind
 * POST /v1/ai/generate   – Authorization: Bearer <COACH_APP_TOKEN>
 *      { "task": "ping", "input": { … }, "images": [{ "mimeType": "image/jpeg", "data": "<base64>" }] }
 */
import { AllProvidersFailed, generate, parseJsonOutput } from "./ai";
import { findTask } from "./tasks";
import { type Deps, defaultDeps, type Env, type ImageInput } from "./types";

export const VERSION = "0.2.0";
export const MAX_BODY_BYTES = 8 * 1024 * 1024;
export const MAX_IMAGES = 4;
const IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/heic", "image/webp"]);

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

/** Vergleich in konstanter Zeit (bezogen auf den Inhalt), damit das Token nicht erraten werden kann. */
export function tokensMatch(given: string, expected: string): boolean {
  const a = new TextEncoder().encode(given);
  const b = new TextEncoder().encode(expected);
  let diff = a.length ^ b.length;
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    diff |= (a[i] ?? 0) ^ (b[i] ?? 0);
  }
  return diff === 0;
}

function parseImages(value: unknown): ImageInput[] | string {
  if (value === undefined) return [];
  if (!Array.isArray(value)) return "images muss eine Liste sein";
  if (value.length > MAX_IMAGES) return `höchstens ${MAX_IMAGES} Bilder`;
  const images: ImageInput[] = [];
  for (const item of value) {
    const { mimeType, data } = (item ?? {}) as Record<string, unknown>;
    if (typeof mimeType !== "string" || !IMAGE_TYPES.has(mimeType)) return "ungültiger Bildtyp";
    if (typeof data !== "string" || data.length === 0) return "Bilddaten fehlen";
    images.push({ mimeType, data });
  }
  return images;
}

export async function handle(request: Request, env: Env, deps: Deps = defaultDeps): Promise<Response> {
  const { pathname } = new URL(request.url);

  if (request.method === "GET" && pathname === "/v1/health") {
    return json(200, {
      status: "ok",
      version: VERSION,
      providers: { gemini: Boolean(env.GEMINI_API_KEY), groq: Boolean(env.GROQ_API_KEY) },
      configured: Boolean(env.COACH_APP_TOKEN),
    });
  }

  if (pathname !== "/v1/ai/generate") return json(404, { error: "Nicht gefunden" });
  if (request.method !== "POST") return json(405, { error: "Nur POST" });

  if (!env.COACH_APP_TOKEN)
    return json(503, { error: "Worker ist nicht konfiguriert (COACH_APP_TOKEN fehlt)" });
  const header = request.headers.get("authorization") ?? "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : "";
  if (!token || !tokensMatch(token, env.COACH_APP_TOKEN)) return json(401, { error: "Nicht autorisiert" });

  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > MAX_BODY_BYTES) return json(413, { error: "Anfrage zu groß" });
  const raw = await request.text();
  if (raw.length > MAX_BODY_BYTES) return json(413, { error: "Anfrage zu groß" });

  let body: Record<string, unknown>;
  try {
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed))
      throw new Error("kein Objekt");
    body = parsed as Record<string, unknown>;
  } catch {
    return json(400, { error: "Ungültiges JSON" });
  }

  const task = findTask(body.task);
  if (!task) return json(400, { error: "Unbekannte Aufgabe" });
  const input = body.input ?? {};
  if (typeof input !== "object" || input === null || Array.isArray(input)) {
    return json(400, { error: "input muss ein Objekt sein" });
  }
  const images = parseImages(body.images);
  if (typeof images === "string") return json(400, { error: images });
  if (images.length > 0 && !task.allowImages)
    return json(400, { error: "Diese Aufgabe nimmt keine Bilder an" });

  const { system, prompt } = task.build(input as Record<string, unknown>);
  try {
    const result = await generate({ system, prompt, json: task.json, images }, env, deps);
    let output: unknown = result.text;
    if (task.json) {
      try {
        output = parseJsonOutput(result.text);
      } catch {
        return json(502, { error: "KI-Antwort ist kein gültiges JSON", model: result.model });
      }
    }
    return json(200, { output, model: result.model, provider: result.provider });
  } catch (error) {
    if (error instanceof AllProvidersFailed) return json(502, { error: error.message });
    deps.log(`[worker] Unerwarteter Fehler: ${String(error)}`);
    return json(500, { error: "Interner Fehler" });
  }
}

export default {
  fetch: (request, env) => handle(request, env),
} satisfies ExportedHandler<Env>;
