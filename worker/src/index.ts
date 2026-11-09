/**
 * Cloudflare Worker „coach-ai“: nimmt Aufgaben der Coach-App entgegen und reicht sie an Gemini bzw.
 * Groq weiter. Die KI-Keys liegen nur hier (Worker-Secrets), nie in der App.
 *
 * GET  /sidestore/<key>/… – private SideStore-Quelle (siehe sidestore.ts)
 * GET  /android/<key>/…  – private Download-Seite der Android-App (siehe android.ts)
 * GET  /v1/health        – ohne Anmeldung, zeigt Version und welche Anbieter konfiguriert sind
 * /v1/league/…          – Rangliste (siehe league.ts), Authorization: Bearer <COACH_APP_TOKEN>
 * POST /v1/ai/generate   – Authorization: Bearer <COACH_APP_TOKEN> oder Gast-Token (siehe auth.ts)
 * POST /v1/invite        – nur Haupt-Token: Gast-Token für eine Einladung
 *      { "task": "ping", "input": { … }, "images": [{ "mimeType": "image/jpeg", "data": "<base64>" }] }
 */
import { AllProvidersFailed, generate, parseJsonOutput } from "./ai";
import { handleAndroid } from "./android";
import { authenticate, expiringGuestToken, newGuestID, principalKey, tokensMatch } from "./auth";
import { handleLeague, type LeagueStore } from "./league";
import { listPriceUsd, parsePreference, providerInfo } from "./providers";
import { handleShare, type ShareStore, sharePage } from "./share";
import { handleSideStore } from "./sidestore";
import { findTask } from "./tasks";
import { readLimited } from "./tasks-util";
import { type Deps, defaultDeps, type Env, type ImageInput } from "./types";

export const VERSION = "0.4.0";
export const MAX_BODY_BYTES = 8 * 1024 * 1024;
export const MAX_IMAGES = 4;
const GUEST_TOKEN_SECONDS = 365 * 24 * 3600;
/** Die App wartet 120 s; vorher soll eine verständliche Antwort kommen statt eines Abbruchs. */
export const AI_DEADLINE_MS = 105_000;
const IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/heic", "image/webp"]);

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
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

export { tokensMatch };

export async function handle(request: Request, env: Env, deps: Deps = defaultDeps): Promise<Response> {
  const { pathname } = new URL(request.url);

  const sidestore = await handleSideStore(request, env.COACH_APP_TOKEN, env.RELEASES);
  if (sidestore) return sidestore;
  const android = await handleAndroid(request, env.COACH_APP_TOKEN, env.RELEASES);
  if (android) return android;

  if (request.method === "GET" && pathname === "/v1/health") {
    return json(200, {
      status: "ok",
      version: VERSION,
      providers: {
        gemini: Boolean(env.GEMINI_API_KEY),
        cerebras: Boolean(env.CEREBRAS_API_KEY),
        groq: Boolean(env.GROQ_API_KEY),
        mistral: Boolean(env.MISTRAL_API_KEY),
      },
      providerList: providerInfo(env),
      configured: Boolean(env.COACH_APP_TOKEN),
    });
  }

  if (request.method === "GET") {
    const page = sharePage(pathname);
    if (page) return page;
  }

  const isLeague = pathname.startsWith("/v1/league/");
  const isShare = pathname.startsWith("/v1/share/");
  const isInvite = pathname === "/v1/invite";
  if (pathname !== "/v1/ai/generate" && !isLeague && !isShare && !isInvite)
    return json(404, { error: "Nicht gefunden" });
  if (!isLeague && !isShare && request.method !== "POST") return json(405, { error: "Nur POST" });

  if (!env.COACH_APP_TOKEN)
    return json(503, { error: "Worker ist nicht konfiguriert (COACH_APP_TOKEN fehlt)" });
  const principal = await authenticate(request.headers.get("authorization") ?? "", env, deps.now());
  if (!principal) return json(401, { error: "Nicht autorisiert" });
  if (env.RATE_LIMITER) {
    const { success } = await env.RATE_LIMITER.limit({ key: principalKey(principal) });
    if (!success) return json(429, { error: "Zu viele Anfragen, bitte kurz warten", code: "rate_limited" });
  }

  if (isInvite) {
    // Nur wer den Worker betreibt, lädt ein; Gäste geben den Ranglisten-Code weiter.
    if (principal.kind !== "owner") return json(403, { error: "Nur mit dem Haupt-Token" });
    const id = newGuestID();
    const expiresAt = Math.floor(deps.now() / 1000) + GUEST_TOKEN_SECONDS;
    return json(200, { id, token: await expiringGuestToken(env.COACH_APP_TOKEN, id, expiresAt) });
  }

  if (isShare) {
    const store = env.LEAGUE as unknown as ShareStore | undefined;
    return (
      (await handleShare(request, store, new Date(deps.now()), principalKey(principal))) ??
      json(404, { error: "Nicht gefunden" })
    );
  }

  if (isLeague) {
    const store = env.LEAGUE as unknown as LeagueStore | undefined;
    return (
      (await handleLeague(request, store, new Date(deps.now()), principalKey(principal))) ??
      json(404, { error: "Nicht gefunden" })
    );
  }

  const raw = await readLimited(request, MAX_BODY_BYTES);
  if (raw === null) return json(413, { error: "Anfrage zu groß" });

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
  // Die Tagesnotiz enthält das fest hinterlegte Profil der Betreiberperson.
  if (body.task === "daily_note" && principal.kind === "guest")
    return json(403, { error: "Diese Aufgabe steht nur dem Haupt-Zugang offen" });
  const input = body.input ?? {};
  if (typeof input !== "object" || input === null || Array.isArray(input)) {
    return json(400, { error: "input muss ein Objekt sein" });
  }
  const images = parseImages(body.images);
  if (typeof images === "string") return json(400, { error: images });
  if (images.length > 0 && !task.allowImages)
    return json(400, { error: "Diese Aufgabe nimmt keine Bilder an" });

  const { system, prompt } = task.build(input as Record<string, unknown>, images.length);
  // Unbrauchbare Antworten (kein JSON, nichts belegt) gelten als Ausfall des Anbieters: Der nächste kommt dran.
  const accept = (text: string): unknown => {
    const output: unknown = task.json ? parseJsonOutput(text) : text;
    return task.ground
      ? task.ground(output, `${system ?? ""}\n${prompt}`, input as Record<string, unknown>)
      : output;
  };
  try {
    const result = await generate(
      {
        system,
        prompt,
        json: task.json,
        images,
        temperature: task.temperature,
        maxOutputTokens: task.maxOutputTokens,
        lowThinking: task.lowThinking,
        deadline: deps.now() + AI_DEADLINE_MS,
        task: String(body.task),
      },
      env,
      deps,
      // Gäste ohne Einwilligung nie an Anbieter, die Eingaben zum Training nutzen dürfen.
      principal.kind === "guest" && body.consent !== true ? "privat" : parsePreference(body.provider),
      accept,
    );
    return json(200, {
      output: result.output,
      model: result.model,
      provider: result.provider,
      ...(result.usage
        ? {
            usage: {
              ...result.usage,
              listPriceUsd: listPriceUsd(result.provider, result.model, result.usage),
            },
          }
        : {}),
    });
  } catch (error) {
    if (error instanceof AllProvidersFailed) {
      // Einzelheiten nur ins Protokoll: Antworttexte der Anbieter gehören nicht in die App.
      deps.log(`[worker] ${String(body.task)}: ${error.message}`);
      return json(502, {
        error:
          error.code === "ai_invalid" ? "KI-Antwort war nicht brauchbar" : "KI-Anbieter nicht erreichbar",
        code: error.code,
      });
    }
    deps.log(`[worker] Unerwarteter Fehler: ${String(error)}`);
    return json(500, { error: "Interner Fehler" });
  }
}

export default {
  fetch: (request, env) => handle(request, env),
} satisfies ExportedHandler<Env>;
