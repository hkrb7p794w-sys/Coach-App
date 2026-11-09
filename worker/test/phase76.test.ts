import { describe, expect, it } from "vitest";
import { authenticate, expiringGuestToken, guestToken } from "../src/auth";
import { handle } from "../src/index";
import { env, fakeDeps, geminiText, groqText } from "./helpers";

const master = env.COACH_APP_TOKEN ?? "";
const answer = '{"ok": true, "gruss": "Hallo"}';

function post(token: string, body: unknown): Request {
  return new Request("https://x/v1/ai/generate", {
    method: "POST",
    headers: { authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
}

describe("Phase 76: Datenschutz und Betrieb", () => {
  it("schickt Gäste ohne Einwilligung nicht an Anbieter mit Training", async () => {
    const guest = await guestToken(master, "abcdefghijk2");
    const deps = fakeDeps([() => groqText(answer)]);
    const response = await handle(post(guest, { task: "ping", provider: "auto" }), env, deps);
    expect(response.status).toBe(200);
    expect(deps.calls[0]?.url).not.toContain("generativelanguage");
  });

  it("nutzt nach der Einwilligung die gewählte Reihenfolge", async () => {
    const guest = await guestToken(master, "abcdefghijk2");
    const deps = fakeDeps([() => geminiText(answer)]);
    const response = await handle(post(guest, { task: "ping", provider: "gemini", consent: true }), env, deps);
    expect(response.status).toBe(200);
    expect(deps.calls[0]?.url).toContain("generativelanguage");
  });

  it("lässt die Betreiberperson entscheiden", async () => {
    const deps = fakeDeps([() => geminiText(answer)]);
    const response = await handle(post(master, { task: "ping", provider: "gemini" }), env, deps);
    expect(response.status).toBe(200);
    expect(deps.calls[0]?.url).toContain("generativelanguage");
  });

  it("gibt das fest hinterlegte Profil nicht an Gäste", async () => {
    const guest = await guestToken(master, "abcdefghijk2");
    const deps = fakeDeps([]);
    const response = await handle(post(guest, { task: "daily_note", input: {}, consent: true }), env, deps);
    expect(response.status).toBe(403);
    expect(deps.calls.length).toBe(0);
  });

  it("lehnt abgelaufene Gast-Tokens ab", async () => {
    const token = await expiringGuestToken(master, "abcdefghijk2", 2_000);
    expect(await authenticate(`Bearer ${token}`, env, 1_000_000)).toEqual({ kind: "guest", id: "abcdefghijk2" });
    expect(await authenticate(`Bearer ${token}`, env, 3_000_000)).toBeNull();
  });

  it("erkennt manipulierte Ablaufdaten", async () => {
    const token = await expiringGuestToken(master, "abcdefghijk2", 2_000);
    const forged = token.replace(".2000.", ".9999999999.");
    expect(await authenticate(`Bearer ${forged}`, env, 1_000_000)).toBeNull();
  });

  it("begrenzt Anfragen je Zugang", async () => {
    const limited = { ...env, RATE_LIMITER: { limit: async () => ({ success: false }) } };
    const deps = fakeDeps([]);
    const response = await handle(post(master, { task: "ping" }), limited, deps);
    expect(response.status).toBe(429);
    expect(deps.calls.length).toBe(0);
  });

  it("bricht bei aufgebrauchtem Tageskontingent nicht mehrfach neu an", async () => {
    const quota = () =>
      new Response('{"error":{"status":"RESOURCE_EXHAUSTED","details":[{"quotaId":"RequestsPerDay-FreeTier"}]}}', {
        status: 429,
      });
    const deps = fakeDeps([quota, () => groqText(answer)]);
    const response = await handle(post(master, { task: "ping", provider: "gemini" }), env, deps);
    expect(response.status).toBe(200);
    expect(deps.calls.filter((call) => call.url.includes("generativelanguage")).length).toBe(1);
  });
});
