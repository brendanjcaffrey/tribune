import type { Newsletter } from "./Library";

export function compareNewslettersForApi(a: Newsletter, b: Newsletter): number {
  if (a.updatedAt != b.updatedAt) {
    return a.updatedAt < b.updatedAt ? 1 : -1;
  } else {
    return b.id - a.id;
  }
}

export function compareNewslettersForDisplay(
  a: Newsletter,
  b: Newsletter,
): number {
  if (a.read != b.read) {
    return a.read ? 1 : -1;
  } else if (a.createdAt != b.createdAt) {
    return a.createdAt < b.createdAt ? 1 : -1;
  } else {
    return b.id - a.id;
  }
}
