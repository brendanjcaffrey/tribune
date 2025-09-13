import "fake-indexeddb/auto";
import { Newsletter } from "../src/Library";
import {
  compareNewslettersForApi,
  compareNewslettersForDisplay,
} from "../src/compareNewsletters";
import { expect, test } from "vitest";

function buildNewsletter(
  id: number,
  timestamp: string,
  read: boolean = false,
): Newsletter {
  return {
    id,
    title: id.toString(),
    author: id.toString(),
    sourceMimeType: "index/html",
    read,
    deleted: false,
    createdAt: timestamp,
    updatedAt: timestamp,
    epubUpdatedAt: timestamp,
    epubVersion: null,
    epubLastAccessedAt: null,
    sourceLastAccessedAt: null,
  };
}

test("should sort first by updated at descending for api", async () => {
  const newsletters = [
    buildNewsletter(1, "2025-01-01 06:00:01.456789+00"),
    buildNewsletter(2, "2025-01-02 06:00:01.456789+00"),
    buildNewsletter(3, "2025-01-03 06:00:01.456789+00"),
  ];
  const sortedNewsletterIds = newsletters
    .sort(compareNewslettersForApi)
    .map((n) => n.id);
  expect(sortedNewsletterIds).toEqual([3, 2, 1]);
});

test("should sort second by id descending for api", async () => {
  const newsletters = [
    buildNewsletter(1, "2025-01-01 06:00:01.456789+00"),
    buildNewsletter(2, "2025-01-01 06:00:01.456789+00"),
    buildNewsletter(3, "2025-01-01 06:00:01.456789+00"),
  ];
  const sortedNewsletterIds = newsletters
    .sort(compareNewslettersForApi)
    .map((n) => n.id);
  expect(sortedNewsletterIds).toEqual([3, 2, 1]);
});

test("should sort first by putting read at the bottom, then by created descending, then by id", async () => {
  const newsletters = [
    buildNewsletter(1, "2025-01-01 06:00:01.456789+00"),
    buildNewsletter(2, "2025-01-02 06:00:01.456789+00", true),
    buildNewsletter(3, "2025-01-03 06:00:01.456789+00"),
    buildNewsletter(4, "2025-01-04 06:00:01.456789+00", true),
    buildNewsletter(5, "2025-01-04 06:00:01.456789+00", true),
  ];
  const sortedNewsletterIds = newsletters
    .sort(compareNewslettersForDisplay)
    .map((n) => n.id);
  expect(sortedNewsletterIds).toEqual([1, 3, 2, 5, 4]);
});
