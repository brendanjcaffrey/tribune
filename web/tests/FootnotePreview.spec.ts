import { afterEach, expect, test } from "vitest";
import { FootnotePreview } from "../src/Epub";

// the markup epub3 uses for a footnote, as it reaches the reader: epub:type has
// already been rewritten to epub_type by the time the spine item is parsed
const ARTICLE = `
  <p>
    you keep the million.<a epub_type="noteref" href="#footnote-1" id="footnote-1-src"> [1] </a>
  </p>
  <aside epub_type="footnote" id="footnote-1">
    <p>
      <a epub_type="noteref" href="#footnote-1-src">[1]</a>
      mechanically this could be
      <a href="https://example.com/memo" id="memo">a client memo</a>.
    </p>
  </aside>
`;

function article(body: string = ARTICLE): Document {
  const doc = document.implementation.createHTMLDocument("article");
  doc.body.innerHTML = body;
  return doc;
}

function noteref(doc: Document, id = "footnote-1-src"): Element {
  return doc.getElementById(id)!;
}

// an iframe of its own document, which is where the reader lives and where the
// preview is put
function reader(body: string = ARTICLE) {
  const iframe = document.createElement("iframe");
  document.body.appendChild(iframe);
  const doc = iframe.contentDocument!;
  doc.body.innerHTML = body;
  return { current: iframe };
}

afterEach(() => {
  FootnotePreview.cancelHide();
  document.body.innerHTML = "";
});

test("extracts the note a noteref points at", () => {
  const doc = article();
  const note = FootnotePreview.extract(doc, noteref(doc))!;
  expect(note).toContain("mechanically this could be");
});

test("keeps the text of the note's link back to the noteref, unlinked", () => {
  const doc = article();
  const note = FootnotePreview.extract(doc, noteref(doc))!;
  expect(note).not.toContain("#footnote-1-src");
  expect(note).toContain("[1]");
});

test("keeps the links the note itself makes", () => {
  const doc = article();
  const note = FootnotePreview.extract(doc, noteref(doc))!;
  expect(note).toContain("https://example.com/memo");
});

// the copy sits in the same document as the note, so a surviving id would be
// found ahead of the original the next time anything is looked up by id
test("strips the ids the note is already using", () => {
  const doc = article();
  const note = FootnotePreview.extract(doc, noteref(doc))!;
  expect(note).not.toContain('id="memo"');
});

test("reads the id out of an href that names a file too", () => {
  const doc = article(
    ARTICLE.replace('href="#footnote-1"', 'href="article.html#footnote-1"'),
  );
  const note = FootnotePreview.extract(doc, noteref(doc))!;
  expect(note).toContain("mechanically this could be");
});

// the link out of a note is a noteref like any other, but what it points at is
// the reference, not a note, and previewing "[1]" would say nothing
test("has nothing to show for the link back out of a note", () => {
  const doc = article();
  const back = doc.querySelector('a[href="#footnote-1-src"]')!;
  expect(FootnotePreview.extract(doc, back)).toBe(null);
});

test("has nothing to show when the note isn't in the document", () => {
  const doc = article(
    ARTICLE.replace('href="#footnote-1"', 'href="#footnote-9"'),
  );
  expect(FootnotePreview.extract(doc, noteref(doc))).toBe(null);
});

test("has nothing to show when the note is nothing but the back link", () => {
  const doc = article(`
    <a epub_type="noteref" href="#footnote-1" id="footnote-1-src">[1]</a>
    <aside epub_type="footnote" id="footnote-1">
      <a epub_type="noteref" href="#footnote-1-src">[1]</a>
    </aside>
  `);
  expect(FootnotePreview.extract(doc, noteref(doc))).toBe(null);
});

const VIEWPORT = { width: 400, height: 600 };
const PREVIEW = { width: 200, height: 100 };

test("sits under the noteref, centred on it", () => {
  const place = FootnotePreview.place(
    { left: 150, top: 200, width: 20, height: 16 },
    PREVIEW,
    VIEWPORT,
  );
  // 150 + 20 / 2 - 200 / 2
  expect(place.left).toBe(60);
  // 200 + 16 + the gap
  expect(place.top).toBe(224);
});

test("goes above the noteref when there is no room below it", () => {
  const place = FootnotePreview.place(
    { left: 150, top: 540, width: 20, height: 16 },
    PREVIEW,
    VIEWPORT,
  );
  // 540 - the gap - 100
  expect(place.top).toBe(432);
});

test("stays on screen beside a noteref at the edge", () => {
  const left = FootnotePreview.place(
    { left: 0, top: 200, width: 20, height: 16 },
    PREVIEW,
    VIEWPORT,
  );
  expect(left.left).toBe(12);

  const right = FootnotePreview.place(
    { left: 380, top: 200, width: 20, height: 16 },
    PREVIEW,
    VIEWPORT,
  );
  // 400 - 12 - 200
  expect(right.left).toBe(188);
});

// a note taller than the screen fits neither above nor below, and the reader
// scrolls it in place rather than losing its top off the top of the screen
test("stays on screen when the note fits nowhere", () => {
  const place = FootnotePreview.place(
    { left: 150, top: 300, width: 20, height: 16 },
    { width: 200, height: 900 },
    VIEWPORT,
  );
  expect(place.top).toBe(12);
});

test("shows the note in the reader and takes it away again", () => {
  const iframeRef = reader();
  const doc = iframeRef.current.contentDocument!;

  expect(FootnotePreview.isOpen(iframeRef)).toBe(false);
  expect(FootnotePreview.show(iframeRef, noteref(doc))).toBe(true);
  expect(FootnotePreview.isOpen(iframeRef)).toBe(true);

  const preview = doc.getElementById(FootnotePreview.ELEMENT_ID)!;
  expect(preview.textContent).toContain("mechanically this could be");
  // outside the body, which is the multi-column box the pages are cut from
  expect(preview.parentElement).toBe(doc.documentElement);
  expect(FootnotePreview.isInside(preview.firstElementChild)).toBe(true);
  expect(FootnotePreview.isInside(doc.body)).toBe(false);

  FootnotePreview.hide(iframeRef);
  expect(FootnotePreview.isOpen(iframeRef)).toBe(false);
});

test("leaves the reader alone when there is no note to show", () => {
  const iframeRef = reader();
  const doc = iframeRef.current.contentDocument!;
  const back = doc.querySelector('a[href="#footnote-1-src"]')!;

  expect(FootnotePreview.show(iframeRef, back)).toBe(false);
  expect(FootnotePreview.isOpen(iframeRef)).toBe(false);
});
