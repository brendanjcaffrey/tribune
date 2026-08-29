import { expect, test } from "vitest";
import {
  EndTracking,
  EpubInteraction,
  type ReadingProgress,
} from "../src/Epub";

function tracking(): { current: EndTracking } {
  return { current: EpubInteraction.createEndTracking() };
}

function scroll(progress: number, atEnd: boolean): ReadingProgress {
  return { progress, atEnd };
}

test("marks read the first time the end is reached", () => {
  const ref = tracking();
  expect(EpubInteraction.shouldMarkRead(ref, scroll(0.5, false))).toBe(false);
  expect(EpubInteraction.shouldMarkRead(ref, scroll(1, true))).toBe(true);
});

test("does not mark read again while sitting on the last page", () => {
  const ref = tracking();
  expect(EpubInteraction.shouldMarkRead(ref, scroll(1, true))).toBe(true);
  expect(EpubInteraction.shouldMarkRead(ref, scroll(1, true))).toBe(false);
});

test("does not mark read when a footnote link jumps to the end", () => {
  const ref = tracking();
  EpubInteraction.shouldMarkRead(ref, scroll(0.2, false));

  ref.current.jumpedByAnchor = true;
  expect(EpubInteraction.shouldMarkRead(ref, scroll(1, true))).toBe(false);
});

test("stays suppressed while paging around inside the footnotes", () => {
  const ref = tracking();
  ref.current.jumpedByAnchor = true;
  expect(EpubInteraction.shouldMarkRead(ref, scroll(1, true))).toBe(false);
  expect(EpubInteraction.shouldMarkRead(ref, scroll(1, true))).toBe(false);
});

test("marks read after a footnote jump once the end is reached by reading", () => {
  const ref = tracking();
  ref.current.jumpedByAnchor = true;
  // the jump lands on the last page
  expect(EpubInteraction.shouldMarkRead(ref, scroll(1, true))).toBe(false);
  // back into the body of the article, which clears the suppression
  expect(EpubInteraction.shouldMarkRead(ref, scroll(0.4, false))).toBe(false);
  // and now scrolling to the end counts
  expect(EpubInteraction.shouldMarkRead(ref, scroll(1, true))).toBe(true);
});
