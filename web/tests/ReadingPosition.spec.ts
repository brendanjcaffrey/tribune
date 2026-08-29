import { expect, test } from "vitest";
import { RefObject } from "react";
import { COLUMN_GAP, EpubInteraction, ReadingPosition } from "../src/Epub";

const CLIENT_WIDTH = 600;
const PAGE_WIDTH = CLIENT_WIDTH + COLUMN_GAP;
const PAGES = 37;
// the last column has no trailing gap
const SCROLL_WIDTH = PAGES * PAGE_WIDTH - COLUMN_GAP;

// a stand-in for the reader's iframe: a horizontally paginated document that
// clamps scrolls to the end the way a browser does
function laidOutIframe(page: number): RefObject<HTMLIFrameElement | null> {
  const maxScroll = SCROLL_WIDTH - CLIENT_WIDTH;
  const state = { scrollX: Math.min(page * PAGE_WIDTH, maxScroll) };
  const iframe = {
    clientWidth: CLIENT_WIDTH,
    contentDocument: { body: { scrollWidth: SCROLL_WIDTH } },
    contentWindow: {
      get scrollX() {
        return state.scrollX;
      },
      scrollTo({ left }: { left: number }) {
        state.scrollX = Math.max(0, Math.min(left, maxScroll));
      },
    },
  };
  return { current: iframe } as unknown as RefObject<HTMLIFrameElement | null>;
}

function storedProgress(ref: RefObject<HTMLIFrameElement | null>): string {
  return ReadingPosition.format(
    EpubInteraction.calculateReadingProgress(ref).progress,
  );
}

test("quantises to four decimal places by truncating", () => {
  expect(ReadingPosition.quantise(0.123456)).toBe(0.1234);
  expect(ReadingPosition.quantise(0.99999)).toBe(0.9999);
  expect(ReadingPosition.format(0.123456)).toBe("0.1234");
  expect(ReadingPosition.format(0)).toBe("0.0000");
  expect(ReadingPosition.format(1)).toBe("1.0000");
});

test("clamps a fraction outside the document", () => {
  expect(ReadingPosition.quantise(-0.5)).toBe(0);
  expect(ReadingPosition.quantise(2)).toBe(1);
  expect(ReadingPosition.quantise(NaN)).toBe(0);
});

test("parses a stored fraction back", () => {
  expect(ReadingPosition.parse("0.3519")).toBe(0.3519);
  expect(ReadingPosition.parse("0.0000")).toBe(0);
  expect(ReadingPosition.parse("1.0000")).toBe(1);
  // a value from a renderer that rounds further out still quantises to ours
  expect(ReadingPosition.parse("0.35196")).toBe(0.3519);
});

test("treats a value that is not a fraction as never opened", () => {
  // the cfis stored before progress became a fraction retire this way
  expect(ReadingPosition.parse("epubcfi(/6/2!/4/2/2/2)")).toBeNull();
  expect(ReadingPosition.parse("")).toBeNull();
  expect(ReadingPosition.parse("   ")).toBeNull();
  expect(ReadingPosition.parse("halfway")).toBeNull();
  expect(ReadingPosition.parse("1.5")).toBeNull();
  expect(ReadingPosition.parse("-0.2")).toBeNull();
  expect(ReadingPosition.parse(null)).toBeNull();
  expect(ReadingPosition.parse(undefined)).toBeNull();
});

test("reports reading progress as a quantised fraction", () => {
  expect(EpubInteraction.calculateReadingProgress(laidOutIframe(0))).toEqual({
    progress: 0,
    atEnd: false,
  });

  const middle = EpubInteraction.calculateReadingProgress(laidOutIframe(13));
  expect(middle.progress).toBe(
    ReadingPosition.quantise((13 * PAGE_WIDTH) / SCROLL_WIDTH),
  );
  expect(middle.progress).toBeGreaterThan(0);
  expect(middle.progress).toBeLessThan(1);
  expect(middle.atEnd).toBe(false);

  expect(
    EpubInteraction.calculateReadingProgress(laidOutIframe(PAGES - 1)).atEnd,
  ).toBe(true);
});

test("a fraction round trips back to the page it was taken from", () => {
  for (let page = 0; page < PAGES; page++) {
    const saved = storedProgress(laidOutIframe(page));

    const reopened = laidOutIframe(0);
    const restored = ReadingPosition.parse(saved);
    expect(restored).not.toBeNull();
    ReadingPosition.scrollToProgress(reopened, restored!);

    expect(reopened.current!.contentWindow!.scrollX).toBe(
      laidOutIframe(page).current!.contentWindow!.scrollX,
    );
  }
});

test("reopening without reading further stores the same value", () => {
  // the server only bumps updated_at when the value differs, so a fraction
  // that jittered on every reopen would churn the sync across clients
  let saved = storedProgress(laidOutIframe(13));

  for (let reopen = 0; reopen < 5; reopen++) {
    const reader = laidOutIframe(0);
    ReadingPosition.scrollToProgress(reader, ReadingPosition.parse(saved)!);
    const resaved = storedProgress(reader);
    expect(resaved).toBe(saved);
    saved = resaved;
  }
});

test("an unparseable stored value opens at the beginning", () => {
  const reader = laidOutIframe(13);
  const restored = ReadingPosition.parse("epubcfi(/6/2!/4/2/2/2)");
  expect(restored).toBeNull();
  // nothing seeks, so a freshly opened reader stays on the first page
  const fresh = laidOutIframe(0);
  expect(fresh.current!.contentWindow!.scrollX).toBe(0);
  expect(storedProgress(fresh)).toBe("0.0000");
  // and the old value is replaced by a fraction as soon as it is read
  expect(storedProgress(reader)).not.toBe("epubcfi(/6/2!/4/2/2/2)");
});

test("a document that fits one screen is fully reached", () => {
  const iframe = {
    clientWidth: CLIENT_WIDTH,
    contentDocument: { body: { scrollWidth: CLIENT_WIDTH } },
    contentWindow: { scrollX: 0, scrollTo() {} },
  } as unknown as HTMLIFrameElement;
  const ref = { current: iframe } as RefObject<HTMLIFrameElement | null>;

  expect(EpubInteraction.calculateReadingProgress(ref)).toEqual({
    progress: 1,
    atEnd: true,
  });
  expect(storedProgress(ref)).toBe("1.0000");
});
