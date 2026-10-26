/**
 * Aufgaben (Prompts) liegen im Worker, nicht in der App: Prompt-Änderungen brauchen so nur einen
 * Worker-Deploy und keine neue App-Version. Die App schickt nur abgeleitete Werte (Datenschutzmodus
 * „reduziert“ entscheidet die App, bevor sie sendet).
 *
 * Regel aus dem Altbestand: Die Regeln entscheiden, die KI formuliert nur.
 */
export interface TaskDefinition {
  json: boolean;
  allowImages: boolean;
  build(input: Record<string, unknown>): { system?: string; prompt: string };
}

const GERMAN = "Schreibe durchgängig in korrektem Deutsch mit echten Umlauten (ä, ö, ü, ß).";

export const TASKS: Record<string, TaskDefinition> = {
  /** Verbindungstest aus den App-Einstellungen. */
  ping: {
    json: true,
    allowImages: false,
    build: () => ({
      prompt: `Antworte ausschließlich mit JSON der Form {"ok": true, "gruss": "<ein kurzer Satz>"}. ${GERMAN}`,
    }),
  },
};

export function findTask(name: unknown): TaskDefinition | undefined {
  return typeof name === "string" && Object.hasOwn(TASKS, name) ? TASKS[name] : undefined;
}
