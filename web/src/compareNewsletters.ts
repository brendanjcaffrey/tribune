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
    // unread first
    return a.read ? 1 : -1;
  } else if (a.createdAt != b.createdAt) {
    // newest first
    return a.createdAt > b.createdAt ? -1 : 1;
  } else {
    return b.id - a.id;
  }
}

export function compareNewslettersForDownloading(
  a: Newsletter,
  b: Newsletter,
): number {
  if (a.createdAt != b.createdAt) {
    // oldest first
    return a.createdAt > b.createdAt ? 1 : -1;
  } else {
    return a.id - b.id;
  }
}
