/** Eingaben begrenzen: Die App ist vertrauenswürdig, aber Prompts sollen nicht beliebig wachsen. */
export function text(value: unknown, max = 600): string {
  if (typeof value === "number" && Number.isFinite(value)) return String(value);
  if (typeof value !== "string") return "";
  return value.replace(/\s+/g, " ").trim().slice(0, max);
}

export function list(value: unknown, maxItems = 12, maxLength = 300): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .slice(0, maxItems)
    .map((item) => text(item, maxLength))
    .filter(Boolean);
}
