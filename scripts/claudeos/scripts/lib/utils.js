export function normalizePath(input) {
  return String(input || "").replace(/\\/g, "/");
}

export function toList(value) {
  if (!value) return [];
  return Array.isArray(value) ? value : [value];
}
