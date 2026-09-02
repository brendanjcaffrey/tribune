import { afterEach, expect, test } from "vitest";
import {
  EndTracking,
  EpubInteraction,
  FootnotePreview,
  type ReadingProgress,
  type TouchStart,
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

test("marks read again after moving away from the end and back", () => {
  const ref = tracking();
  expect(EpubInteraction.shouldMarkRead(ref, scroll(1, true))).toBe(true);
  expect(EpubInteraction.shouldMarkRead(ref, scroll(0.4, false))).toBe(false);
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

function touchStart(
  targetIsAnchorOrButton: boolean,
  targetIsInsidePreview = false,
) {
  return {
    current: { x: 10, y: 10, targetIsAnchorOrButton, targetIsInsidePreview },
  };
}

// a touch that ended somewhere other than where it started
function swipe(target: EventTarget | null, endX: number) {
  const event = tap(target);
  return Object.create(event, {
    changedTouches: { value: [{ clientX: endX, clientY: 10 }] },
  }) as typeof event;
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
  EpubInteraction.handleFootnoteClick(iframeRef, event as unknown as Event);

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
    touchStart(false, true),
    event as unknown as TouchEvent,
  );

  expect(FootnotePreview.isOpen(iframeRef)).toBe(true);
  expect(event.defaultPrevented).toBe(true);
});

test("a swipe that starts on the note scrolls it rather than the page", () => {
  const iframeRef = reader();
  const doc = iframeRef.current.contentDocument!;
  FootnotePreview.show(iframeRef, doc.getElementById("footnote-1-src")!);

  // a finger that drifts off the box mid swipe still ends on the note, since a
  // touch stays with the element it started on
  const preview = doc.getElementById(FootnotePreview.ELEMENT_ID)!;
  const event = swipe(preview.firstElementChild, 200);
  let turned = false;
  EpubInteraction.handleTouchEnd(
    iframeRef,
    touchStart(false, true),
    event as unknown as TouchEvent,
    () => {
      turned = true;
    },
  );

  expect(FootnotePreview.isOpen(iframeRef)).toBe(true);
  expect(turned).toBe(false);
});

test("a swipe that starts away from the note turns the page", () => {
  const iframeRef = reader();
  const doc = iframeRef.current.contentDocument!;
  FootnotePreview.show(iframeRef, doc.getElementById("footnote-1-src")!);

  const event = swipe(doc.body, 200);
  EpubInteraction.handleTouchEnd(
    iframeRef,
    touchStart(false),
    event as unknown as TouchEvent,
  );

  expect(FootnotePreview.isOpen(iframeRef)).toBe(false);
  expect(event.defaultPrevented).toBe(true);
});

test("a touch is recorded as starting on the note when it lands inside it", () => {
  const iframeRef = reader();
  const doc = iframeRef.current.contentDocument!;
  FootnotePreview.show(iframeRef, doc.getElementById("footnote-1-src")!);

  const preview = doc.getElementById(FootnotePreview.ELEMENT_ID)!;
  const ref: { current: TouchStart | null } = { current: null };
  EpubInteraction.handleTouchStart(ref, {
    touches: [{ clientX: 10, clientY: 10 }],
    target: preview.firstElementChild,
  } as unknown as TouchEvent);

  expect(ref.current?.targetIsInsidePreview).toBe(true);

  EpubInteraction.handleTouchStart(ref, {
    touches: [{ clientX: 10, clientY: 10 }],
    target: doc.body,
  } as unknown as TouchEvent);

  expect(ref.current?.targetIsInsidePreview).toBe(false);
});

test("turning the page puts an open preview away", () => {
  const iframeRef = reader();
  const doc = iframeRef.current.contentDocument!;
  FootnotePreview.show(iframeRef, doc.getElementById("footnote-1-src")!);

  EpubInteraction.scrollPage(iframeRef, "forward");

  expect(FootnotePreview.isOpen(iframeRef)).toBe(false);
});

// jsdom lays nothing out, so the paginated geometry that decides "last page"
// has to be described rather than measured
function paginated(pages: number, onPage: number) {
  const iframe = document.createElement("iframe");
  document.body.appendChild(iframe);
  const clientWidth = 100;
  Object.defineProperty(iframe, "clientWidth", { value: clientWidth });
  Object.defineProperty(iframe.contentDocument!.body, "scrollWidth", {
    value: clientWidth * pages,
  });
  Object.defineProperty(iframe.contentWindow!, "scrollX", {
    value: clientWidth * onPage,
  });
  const scrolled: number[] = [];
  iframe.contentWindow!.scrollBy = (options?: ScrollToOptions | number) => {
    scrolled.push(typeof options === "number" ? options : options!.left!);
  };
  return { iframeRef: { current: iframe }, scrolled };
}

function arrowRight() {
  return { key: "ArrowRight", target: null } as unknown as KeyboardEvent;
}

test("a page turn forward on the last page marks the newsletter read", () => {
  const { iframeRef, scrolled } = paginated(3, 2);
  let markedRead = false;

  EpubInteraction.handleKeyDown(
    iframeRef,
    arrowRight(),
    () => {},
    () => {
      markedRead = true;
    },
  );

  expect(markedRead).toBe(true);
  expect(scrolled).toEqual([]);
});

test("a page turn forward mid-document turns the page instead", () => {
  const { iframeRef, scrolled } = paginated(3, 1);
  let markedRead = false;

  EpubInteraction.handleKeyDown(
    iframeRef,
    arrowRight(),
    () => {},
    () => {
      markedRead = true;
    },
  );

  expect(markedRead).toBe(false);
  expect(scrolled.length).toBe(1);
});

test("a page turn forward on the only page marks the newsletter read", () => {
  // one screen of content never paginates, so there is no last page to arrive
  // at by scrolling - the turn is the only signal there is
  const { iframeRef } = paginated(1, 0);
  let markedRead = false;

  EpubInteraction.handleKeyDown(
    iframeRef,
    arrowRight(),
    () => {},
    () => {
      markedRead = true;
    },
  );

  expect(markedRead).toBe(true);
});

test("a swipe forward on the last page marks the newsletter read", () => {
  const { iframeRef } = paginated(3, 2);
  let markedRead = false;

  const event = {
    target: iframeRef.current.contentDocument!.body,
    changedTouches: [{ clientX: 10, clientY: 10 }],
    preventDefault: () => {},
  };
  EpubInteraction.handleTouchEnd(
    iframeRef,
    {
      current: {
        x: 200,
        y: 10,
        targetIsAnchorOrButton: false,
        targetIsInsidePreview: false,
      },
    },
    event as unknown as TouchEvent,
    () => {
      markedRead = true;
    },
  );

  expect(markedRead).toBe(true);
});

test("a backward page turn at the start marks nothing", () => {
  const { iframeRef } = paginated(3, 0);
  let markedRead = false;

  EpubInteraction.scrollPage(iframeRef, "backward", () => {
    markedRead = true;
  });

  expect(markedRead).toBe(false);
});
