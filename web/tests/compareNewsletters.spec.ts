import "fake-indexeddb/auto";
import { Newsletter } from "../src/Library";
import { compareNewslettersForApi } from "../src/compareNewsletters";
import { expect, test, vi } from "vitest";

function buildNewsletter(id: number, timestamp: string): Newsletter {
  return {
    id,
    title: id.toString(),
    author: id.toString(),
    sourceMimeType: "index/html",
    read: false,
    deleted: false,
    createdAt: timestamp,
    updatedAt: timestamp,
    epubUpdatedAt: timestamp,
    epubDownloadedAt: null,
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
