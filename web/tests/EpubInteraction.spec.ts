import { afterEach, expect, test } from "vitest";
import {
  EndTracking,
  EpubInteraction,
  FootnotePreview,
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

// the ios reader previews a note on tap, which puts something on screen that
// the next tap has to be able to put away again rather than turning the page
const ARTICLE = `
  <p>
    you keep the million.<a epub_type="noteref" href="#footnote-1" id="footnote-1-src"> [1] </a>
  </p>
  <aside epub_type="footnote" id="footnote-1">
    <p>mechanically this could be a client memo.</p>
  </aside>
`;

function reader() {
  const iframe = document.createElement("iframe");
  document.body.appendChild(iframe);
  iframe.contentDocument!.body.innerHTML = ARTICLE;
  return { current: iframe };
}

// enough of a touch for handleTouchEnd: where it ended, and what it landed on
function tap(target: EventTarget | null) {
  let defaultPrevented = false;
  return {
    target,
    changedTouches: [{ clientX: 10, clientY: 10 }],
    preventDefault: () => {
      defaultPrevented = true;
    },
    get defaultPrevented() {
      return defaultPrevented;
    },
  };
}

function touchStart(targetIsAnchorOrButton: boolean) {
  return { current: { x: 10, y: 10, targetIsAnchorOrButton } };
}

afterEach(() => {
  FootnotePreview.cancelHide();
  document.body.innerHTML = "";
});

test("a tap on a noteref previews the note instead of jumping to it", () => {
  const iframeRef = reader();
  const doc = iframeRef.current.contentDocument!;
  const noteref = doc.getElementById("footnote-1-src")!;

  const event = tap(noteref);
  EpubInteraction.handleFootnoteClick(
    iframeRef,
    event as unknown as Event,
    tracking(),
  );

  expect(FootnotePreview.isOpen(iframeRef)).toBe(true);
  // the noteref keeps its href, so the frame would follow it as well without
  // this
  expect(event.defaultPrevented).toBe(true);
});

test("a tap away from an open preview puts it away rather than turning the page", () => {
  const iframeRef = reader();
  const doc = iframeRef.current.contentDocument!;
  FootnotePreview.show(iframeRef, doc.getElementById("footnote-1-src")!);

  const event = tap(doc.body);
  EpubInteraction.handleTouchEnd(
    iframeRef,
    touchStart(false),
    event as unknown as TouchEvent,
  );

  expect(FootnotePreview.isOpen(iframeRef)).toBe(false);
  expect(event.defaultPrevented).toBe(true);
});

test("a tap on the note itself leaves it up", () => {
  const iframeRef = reader();
  const doc = iframeRef.current.contentDocument!;
  FootnotePreview.show(iframeRef, doc.getElementById("footnote-1-src")!);

  const preview = doc.getElementById(FootnotePreview.ELEMENT_ID)!;
  const event = tap(preview.firstElementChild);
  EpubInteraction.handleTouchEnd(
    iframeRef,
    touchStart(false),
    event as unknown as TouchEvent,
  );

  expect(FootnotePreview.isOpen(iframeRef)).toBe(true);
  expect(event.defaultPrevented).toBe(true);
});

test("turning the page puts an open preview away", () => {
  const iframeRef = reader();
  const doc = iframeRef.current.contentDocument!;
  FootnotePreview.show(iframeRef, doc.getElementById("footnote-1-src")!);

  EpubInteraction.scrollPage(iframeRef, "forward");

  expect(FootnotePreview.isOpen(iframeRef)).toBe(false);
});
