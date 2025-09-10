import type { Newsletter } from "./Library";

export function compareNewslettersForApi(a: Newsletter, b: Newsletter): number {
  if (a.updatedAt != b.updatedAt) {
    return a.updatedAt < b.updatedAt ? 1 : -1;
  } else {
    return b.id - a.id;
  }
}
