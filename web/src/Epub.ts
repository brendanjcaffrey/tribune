import JSZip from "jszip";
import { RefObject } from "react";

export interface SpineItem {
  headContent: string;
  bodyContent: string;
}

interface ManifestItem {
  id: string;
  href: string;
  mediaType: string;
}

export interface TouchStart {
  x: number;
  y: number;
  targetIsAnchorOrButton: boolean;
}

// whether a tap or click on a noteref jumps to the note at the back of the
// article or shows it in place. the web does both - it previews on hover and
// jumps on click - so only ios asks for "preview"
export type FootnoteClickBehavior = "jump" | "preview";

export interface Box {
  left: number;
  top: number;
  width: number;
  height: number;
}

export interface Size {
  width: number;
  height: number;
}

export interface Placement {
  left: number;
  top: number;
}

// the anchors epub marks up as references to a note. epub:type is rewritten to
// epub_type when the spine item is parsed
const NOTEREF_SELECTOR = "a[epub_type]";

// event targets come from inside the reader's iframe, which is a different
// realm, so instanceof Element would say no. ask for closest instead
function closestElement(
  target: EventTarget | null,
  selector: string,
): Element | null {
  const element = target as {
    closest?: (selector: string) => Element | null;
  } | null;
  return element?.closest?.(selector) ?? null;
}

// the part of a link after the "#", which is the id of the element it points at
function fragmentId(href: string | null | undefined): string | null {
  if (!href) return null;
  const hash = href.indexOf("#");
  if (hash < 0) return null;
  return href.substring(hash + 1) || null;
}

function clamp(value: number, lowest: number, highest: number): number {
  return Math.min(Math.max(value, lowest), highest);
}

export interface ReadingProgress {
  // a fraction of the document between 0 and 1, quantised to four decimal
  // places by ReadingPosition.quantise
  progress: number;
  atEnd: boolean;
}

// state behind "mark as read once the end is reached". it lives outside
// calculateReadingProgress because the end has to be newly reached, which only
// a value that survives between scroll events can tell us
export interface EndTracking {
  wasAtEnd: boolean;
}

export const COLUMN_GAP = 40;
const SWIPE_THRESHOLD = 50;
const TEXT_EXTENSIONS = [
  ".xhtml",
  ".html",
  ".xml",
  ".opf",
  ".ncx",
  ".css",
  ".js",
];

// progress is a fraction of the document between 0 and 1, quantised to four
// decimal places. koreader quantises the same way, so no renderer's value
// disagrees with another's, and reopening a newsletter without reading further
// yields the string that is already stored rather than a jittering float that
// would churn the sync
const PROGRESS_PLACES = 4;
const PROGRESS_SCALE = 10 ** PROGRESS_PLACES;

export class ReadingPosition {
  // truncates rather than rounding to nearest, matching koreader's
  // math.floor(p * 10000) / 10000
  static quantise(fraction: number): number {
    if (!Number.isFinite(fraction)) {
      return 0;
    }
    const clamped = Math.min(Math.max(fraction, 0), 1);
    return Math.floor(clamped * PROGRESS_SCALE) / PROGRESS_SCALE;
  }

  // the decimal string that gets stored and synced
  static format(fraction: number): string {
    return ReadingPosition.quantise(fraction).toFixed(PROGRESS_PLACES);
  }

  // a stored value that isn't a fraction means the newsletter has never been
  // opened, so it opens at the beginning. that is what retires the epub cfis
  // stored before progress became a fraction: nothing migrates them, each is
  // overwritten the first time its newsletter is opened
  static parse(stored: string | null | undefined): number | null {
    if (typeof stored !== "string" || stored.trim() === "") {
      return null;
    }
    const value = Number(stored);
    if (!Number.isFinite(value) || value < 0 || value > 1) {
      return null;
    }
    return ReadingPosition.quantise(value);
  }

  static scrollToProgress(
    iframeRef: RefObject<HTMLIFrameElement | null>,
    fraction: number,
  ) {
    const { current: iframe } = iframeRef;
    if (!iframe || !iframe.contentWindow || !iframe.contentDocument) {
      return;
    }

    const pageWidth = iframe.clientWidth + COLUMN_GAP;
    if (pageWidth <= 0) {
      return;
    }

    // land on a page boundary, which is the only place the reader ever sits.
    // rounding to the nearest page is what makes reopening stable: quantising
    // truncated the fraction, so it points a hair short of the page it came
    // from, and the nearest page is that one again
    const scrollWidth = iframe.contentDocument.body.scrollWidth;
    const page = Math.round((fraction * scrollWidth) / pageWidth);
    iframe.contentWindow.scrollTo({
      left: page * pageWidth,
      behavior: "instant",
    });
  }
}

export class Epub {
  private files = new Map<string, string | Blob>();
  rootfilePath: string | undefined;
  manifest = new Map<string, ManifestItem>();
  spine: string[] = [];

  constructor(private data: ArrayBuffer | Uint8Array) {}

  public async parse() {
    await this.unzip();
    this.rootfilePath = this.getRootfilePath();
    await this.parseRootfile();
  }

  private async unzip() {
    const zip = await JSZip.loadAsync(this.data);
    for (const [relativePath, zipEntry] of Object.entries(zip.files)) {
      if (!zipEntry.dir) {
        let content: string | Blob;
        const extension = relativePath.split(".").pop()?.toLowerCase() || "";
        if (TEXT_EXTENSIONS.includes(`.${extension}`)) {
          content = await zipEntry.async("text");
        } else {
          content = await zipEntry.async("blob");
        }
        this.files.set(relativePath, content);
      }
    }
  }

  private getRootfilePath(): string {
    const containerXmlPath = "META-INF/container.xml";
    const containerXml = this.files.get(containerXmlPath);

    if (!containerXml || typeof containerXml !== "string") {
      throw new Error(`'${containerXmlPath}' not found in EPUB`);
    }

    const parser = new DOMParser();
    const doc = parser.parseFromString(containerXml, "application/xml");
    const rootfile = doc.querySelector("rootfile");

    if (!rootfile) {
      throw new Error("No <rootfile> element found in container.xml");
    }

    const fullPath = rootfile.getAttribute("full-path");
    if (!fullPath) {
      throw new Error('No "full-path" attribute found on <rootfile> element');
    }

    if (!this.files.has(fullPath)) {
      throw new Error(`Root file "${fullPath}" not found in EPUB`);
    }

    return fullPath;
  }

  private async parseRootfile() {
    if (!this.rootfilePath) {
      throw new Error("Root file path not found.");
    }

    const rootfileContent = this.files.get(this.rootfilePath);
    if (!rootfileContent || typeof rootfileContent !== "string") {
      throw new Error("Root file content not found or not a string.");
    }

    const parser = new DOMParser();
    const doc = parser.parseFromString(rootfileContent, "application/xml");

    // parse manifest
    const manifestItems = doc.querySelectorAll("manifest item");
    manifestItems.forEach((item) => {
      const id = item.getAttribute("id");
      const href = item.getAttribute("href");
      const mediaType = item.getAttribute("media-type");
      if (id && href && mediaType) {
        const hrefPath = this.resolvePath(href, this.rootfilePath!);
        this.manifest.set(id, { id, href: hrefPath, mediaType });
      }
    });

    // parse spine
    const spineItems = doc.querySelectorAll("spine itemref");
    spineItems.forEach((item) => {
      const idref = item.getAttribute("idref");
      if (idref) {
        this.spine.push(idref);
      }
    });
  }

  public async getSpineItem(
    spineIndex: number,
    externalLinkBehavior: "target _blank" | "event",
    footnoteClickBehavior: FootnoteClickBehavior,
  ): Promise<SpineItem> {
    if (spineIndex < 0 || spineIndex >= this.spine.length) {
      throw new Error("Spine index out of bounds");
    }

    const idref = this.spine[spineIndex];
    const manifestItem = this.manifest.get(idref);

    if (!manifestItem) {
      throw new Error(`Item with idref "${idref}" not found in manifest`);
    }

    const itemPath = manifestItem.href;
    const itemContent = this.files.get(itemPath);

    if (!itemContent || typeof itemContent !== "string") {
      throw new Error(`Content for "${itemPath}" not found or not a string`);
    }

    // DOMParser chokes on these epub:type attributes, so we replace them
    const contentWithFixedFootnotes = itemContent.replaceAll(
      "epub:type",
      "epub_type",
    );

    const parser = new DOMParser();
    const doc = parser.parseFromString(
      contentWithFixedFootnotes,
      "application/xhtml+xml",
    );

    // update links - any footnote links should navigate and other links should open in a new tab
    const anchors = doc.querySelectorAll("a");
    for (const anchor of Array.from(anchors)) {
      const href = anchor.getAttribute("href");
      if (anchor.hasAttribute("epub_type")) {
        // "preview" leaves the noteref alone. the reader shows the note in
        // place instead, wired up on the document rather than on the anchor
        if (href && footnoteClickBehavior === "jump") {
          anchor.setAttribute(
            "onclick",
            `window.parent.dispatchEvent(new CustomEvent('scrollToHref', { detail: { href: '${href}' } })); return false;`,
          );
        }
      } else {
        if (href && (href.startsWith("http") || href.startsWith("https"))) {
          if (externalLinkBehavior === "event") {
            anchor.setAttribute(
              "onclick",
              `window.parent.dispatchEvent(new CustomEvent('openExternalLink', { detail: { href: '${href}' } })); return false;`,
            );
          } else {
            anchor.setAttribute("target", "_blank");
            anchor.setAttribute("rel", "noopener noreferrer");
          }
        }
      }
    }

    // inline images
    const images = doc.querySelectorAll("img");
    for (const img of Array.from(images)) {
      const src = img.getAttribute("src");
      if (src) {
        const imagePath = this.resolvePath(src, itemPath);
        const imageBlob = this.files.get(imagePath);
        if (imageBlob instanceof Blob) {
          const dataUrl = await this.blobToDataURL(imageBlob);
          img.setAttribute("src", dataUrl);
        }
      }
    }

    // inline stylesheets
    const links = doc.querySelectorAll('link[rel="stylesheet"]');
    for (const link of Array.from(links)) {
      const href = link.getAttribute("href");
      if (href) {
        const cssPath = this.resolvePath(href, itemPath);
        const cssContent = this.files.get(cssPath);
        if (typeof cssContent === "string") {
          const style = doc.createElement("style");
          style.textContent = cssContent;
          link.replaceWith(style);
        }
      }
    }

    return { headContent: doc.head.innerHTML, bodyContent: doc.body.innerHTML };
  }

  private resolvePath(href: string, basePath: string): string {
    const base = basePath.substring(0, basePath.lastIndexOf("/"));
    const pathParts = (base + "/" + href).split("/");
    const resolvedParts: string[] = [];
    for (const part of pathParts) {
      if (part === "." || part === "") continue;
      if (part === "..") {
        resolvedParts.pop();
      } else {
        resolvedParts.push(part);
      }
    }
    return resolvedParts.join("/");
  }

  private blobToDataURL(blob: Blob): Promise<string> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(reader.result as string);
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  }

  static buildIframeContent(
    columnWidth: number,
    muiStyles: string,
    bookContent: SpineItem | null,
    maxImageSize: number,
  ): string {
    return `
          <html>
            <head>
              <style>
                html {
                  height: 100%;
                  overflow: hidden;
                  scroll-snap-type: x mandatory;
                }
                body {
                  height: 100%;
                  margin: 0;
                  padding: 0;
                  box-sizing: border-box;

                  column-width: ${columnWidth}px;
                  column-gap: ${COLUMN_GAP}px;

                  text-align: justify;

                  overflow-wrap: anywhere;
                  word-break: break-word;
                }
                pre, code {
                  white-space: pre-wrap;
                  overflow-wrap: anywhere;
                }
                table, svg, video, iframe {
                  max-width: 100%;
                }
                img {
                  max-width: ${maxImageSize}%;
                  max-height: ${maxImageSize}vh;
                  object-fit: contain;
                }
                #${FootnotePreview.ELEMENT_ID} {
                  position: fixed;
                  left: 0;
                  top: 0;
                  z-index: 2147483647;
                  box-sizing: border-box;
                  max-width: min(320px, calc(100vw - 24px));
                  max-height: 45vh;
                  overflow-y: auto;
                  padding: 12px 14px;
                  border-radius: 8px;
                  text-align: left;
                  /* the ground and the typography are copied off the body when
                     the preview is shown, because each platform sets up its own
                     palette and the preview hangs outside the body */
                  box-shadow:
                    0 0 0 1px rgba(128, 128, 128, 0.35),
                    0 2px 12px rgba(0, 0, 0, 0.3);
                }
                #${FootnotePreview.ELEMENT_ID} > :first-child {
                  margin-top: 0;
                }
                #${FootnotePreview.ELEMENT_ID} > :last-child {
                  margin-bottom: 0;
                }
                #${FootnotePreview.ELEMENT_ID} img {
                  max-width: 100%;
                }
                #__blank_epub_column {
                  display: inline-block;
                  height: 1px;
                  /* make sure it doesn't visibly affect layout other than occupying a column */
                  break-inside: avoid;
                }
                ${muiStyles}
                ${bookContent?.headContent ?? ""}
              </style>
            </head>
            <body>
              ${bookContent?.bodyContent ?? ""}
            </body>
          </html>
        `;
  }
}

// a note shown in place beside the noteref pointing at it.
//
// it lives in the reader's iframe, off the root element rather than the body,
// because the body is the multi-column box the pages are cut from and the
// preview has to sit still in the viewport instead of flowing into a column
export class FootnotePreview {
  static readonly ELEMENT_ID = "__footnote_preview";

  // how far the preview keeps off the noteref and off the edge of the screen
  private static readonly GAP = 8;
  private static readonly MARGIN = 12;

  // the pointer usually crosses a little body text on its way from the noteref
  // into the preview, so hiding waits a moment for it to arrive
  private static readonly HIDE_DELAY_MS = 200;
  private static hideTimer: ReturnType<typeof setTimeout> | null = null;

  static isInside(target: EventTarget | null): boolean {
    return closestElement(target, `#${FootnotePreview.ELEMENT_ID}`) !== null;
  }

  static isOpen(iframeRef: RefObject<HTMLIFrameElement | null>): boolean {
    const doc = iframeRef.current?.contentDocument;
    return doc?.getElementById(FootnotePreview.ELEMENT_ID) != null;
  }

  // the note a noteref points at, ready to drop into the preview, or null when
  // there is nothing worth showing
  static extract(doc: Document, noteref: Element): string | null {
    const id = fragmentId(noteref.getAttribute("href"));
    if (!id) return null;

    const note = doc.getElementById(id);
    if (!note) return null;
    // a noteref pointing at another noteref is the link back out of a note, not
    // a note of its own, so there is nothing to preview
    if (note.tagName.toLowerCase() === "a") return null;

    // a note opens with a link back to the noteref, which is navigation the
    // preview has no use for - the reader never left
    const backHref = noteref.id ? `#${noteref.id}` : null;
    const isBackLink = (link: Element) =>
      backHref === null || link.getAttribute("href") === backHref;

    // the marker the link back carries reads as part of the note, so it stays
    // behind as plain text
    const copy = note.cloneNode(true) as Element;
    for (const link of Array.from(copy.querySelectorAll(NOTEREF_SELECTOR))) {
      if (isBackLink(link)) link.replaceWith(...Array.from(link.childNodes));
    }

    // remove duplicate ids
    copy.removeAttribute("id");
    for (const element of Array.from(copy.querySelectorAll("[id]"))) {
      element.removeAttribute("id");
    }

    // the marker isn't something the note says though, so a note that is
    // nothing but the link back has nothing worth showing
    const said = note.cloneNode(true) as Element;
    for (const link of Array.from(said.querySelectorAll(NOTEREF_SELECTOR))) {
      if (isBackLink(link)) link.remove();
    }

    return said.textContent?.trim() ? copy.innerHTML : null;
  }

  // below the noteref by default, above it when there is not enough room below
  static place(anchor: Box, preview: Size, viewport: Size): Placement {
    const { GAP, MARGIN } = FootnotePreview;

    const rightmost = Math.max(MARGIN, viewport.width - MARGIN - preview.width);
    const left = clamp(
      anchor.left + anchor.width / 2 - preview.width / 2,
      MARGIN,
      rightmost,
    );

    const below = anchor.top + anchor.height + GAP;
    const above = anchor.top - GAP - preview.height;
    const lowest = Math.max(MARGIN, viewport.height - MARGIN - preview.height);
    const wanted = below <= lowest ? below : above >= MARGIN ? above : lowest;

    return { left, top: clamp(wanted, MARGIN, lowest) };
  }

  // shows the note the noteref points at and returns whether there was one
  static show(
    iframeRef: RefObject<HTMLIFrameElement | null>,
    noteref: Element,
  ): boolean {
    const iframe = iframeRef.current;
    const doc = iframe?.contentDocument;
    const view = iframe?.contentWindow;
    if (!doc || !view) return false;

    const content = FootnotePreview.extract(doc, noteref);
    if (content === null) return false;

    FootnotePreview.cancelHide();

    let preview = doc.getElementById(FootnotePreview.ELEMENT_ID);
    if (!preview) {
      preview = doc.createElement("div");
      preview.id = FootnotePreview.ELEMENT_ID;
      doc.documentElement.appendChild(preview);
    }
    preview.innerHTML = content;

    // adding to the root element means inheriting none of the reader's
    // typography, so copy it off the body
    const body = view.getComputedStyle(doc.body);
    preview.style.background = body.backgroundColor;
    preview.style.color = body.color;
    preview.style.fontFamily = body.fontFamily;
    preview.style.fontSize = body.fontSize;
    preview.style.lineHeight = body.lineHeight;

    const placement = FootnotePreview.place(
      noteref.getBoundingClientRect(),
      { width: preview.offsetWidth, height: preview.offsetHeight },
      { width: view.innerWidth, height: view.innerHeight },
    );
    preview.style.left = `${placement.left}px`;
    preview.style.top = `${placement.top}px`;
    return true;
  }

  static hide(iframeRef: RefObject<HTMLIFrameElement | null>) {
    FootnotePreview.cancelHide();
    iframeRef.current?.contentDocument
      ?.getElementById(FootnotePreview.ELEMENT_ID)
      ?.remove();
  }

  static scheduleHide(iframeRef: RefObject<HTMLIFrameElement | null>) {
    if (FootnotePreview.hideTimer !== null) return;
    FootnotePreview.hideTimer = setTimeout(() => {
      FootnotePreview.hideTimer = null;
      FootnotePreview.hide(iframeRef);
    }, FootnotePreview.HIDE_DELAY_MS);
  }

  static cancelHide() {
    if (FootnotePreview.hideTimer !== null) {
      clearTimeout(FootnotePreview.hideTimer);
      FootnotePreview.hideTimer = null;
    }
  }
}

// this code is used by both the typescript/react web app and a plain
// javascript webview in the ios app so some indirection is needed
export class EpubInteraction {
  static handleKeyDown(
    iframeRef: RefObject<HTMLIFrameElement | null>,
    event: KeyboardEvent,
    closeNewsletter: () => void,
    onPastEnd?: () => void,
  ) {
    const tag = (event.target as HTMLElement)?.tagName?.toLowerCase();
    if (
      tag === "input" ||
      tag === "textarea" ||
      (event.target as HTMLElement)?.isContentEditable
    ) {
      return;
    }

    if (event.key === "Escape") {
      closeNewsletter();
      return;
    }

    if (event.key === "ArrowRight") {
      EpubInteraction.scrollPage(iframeRef, "forward", onPastEnd);
    } else if (event.key === "ArrowLeft") {
      EpubInteraction.scrollPage(iframeRef, "backward");
    }
  }

  static handleTouchStart(
    touchStartRef: RefObject<TouchStart | null>,
    event: TouchEvent,
  ) {
    if (event.touches.length === 1) {
      touchStartRef.current = {
        x: event.touches[0].clientX,
        y: event.touches[0].clientY,
        targetIsAnchorOrButton:
          (event.target as HTMLElement).closest("a") != null ||
          (event.target as HTMLElement).closest("button") != null,
      };
    }
  }

  static handleTouchEnd(
    iframeRef: RefObject<HTMLIFrameElement | null>,
    touchStartRef: RefObject<TouchStart | null>,
    event: TouchEvent,
    onPastEnd?: () => void,
  ) {
    if (touchStartRef.current && event.changedTouches.length === 1) {
      const touchEndX = event.changedTouches[0].clientX;
      const touchStartX = touchStartRef.current.x;
      const deltaX = touchEndX - touchStartX;

      if (Math.abs(deltaX) >= SWIPE_THRESHOLD) {
        EpubInteraction.scrollPage(
          iframeRef,
          deltaX < 0 ? "forward" : "backward",
          onPastEnd,
        );
        event.preventDefault();
      } else {
        const insidePreview = FootnotePreview.isInside(event.target);
        if (touchStartRef.current.targetIsAnchorOrButton) {
          // nop, let the link work normally
        } else if (insidePreview) {
          // a tap on the note itself neither turns the page nor dismisses it
          event.preventDefault();
        } else if (FootnotePreview.isOpen(iframeRef)) {
          // a tap anywhere else hides the note
          FootnotePreview.hide(iframeRef);
          event.preventDefault();
        } else if (iframeRef.current?.contentWindow) {
          const screenWidth = iframeRef.current.clientWidth;
          EpubInteraction.scrollPage(
            iframeRef,
            touchEndX < screenWidth / 2 ? "backward" : "forward",
            onPastEnd,
          );
          event.preventDefault();
        }
      }
      touchStartRef.current = null;
    }
  }

  static handleScrollToHref(
    iframeRef: RefObject<HTMLIFrameElement | null>,
    event: Event,
  ) {
    const id = fragmentId((event as CustomEvent).detail.href);
    if (id) {
      EpubInteraction.scrollToId(iframeRef, id);
    }
  }

  static handleFootnoteHover(
    iframeRef: RefObject<HTMLIFrameElement | null>,
    event: Event,
  ) {
    const noteref = closestElement(event.target, NOTEREF_SELECTOR);
    if (noteref) {
      FootnotePreview.show(iframeRef, noteref);
    } else if (FootnotePreview.isInside(event.target)) {
      // the pointer made it into the preview, so it stays up for as long as it
      // is being read
      FootnotePreview.cancelHide();
    } else {
      FootnotePreview.scheduleHide(iframeRef);
    }
  }

  static handleFootnoteHoverOut(
    iframeRef: RefObject<HTMLIFrameElement | null>,
    event: Event,
  ) {
    if ((event as MouseEvent).relatedTarget === null) {
      FootnotePreview.scheduleHide(iframeRef);
    }
  }

  static handleFootnoteClick(
    iframeRef: RefObject<HTMLIFrameElement | null>,
    event: Event,
  ) {
    const noteref = closestElement(event.target, NOTEREF_SELECTOR);
    if (!noteref) return;

    // the noteref keeps its href, so without this the frame would navigate to
    // the note as well as previewing it
    event.preventDefault();
    if (FootnotePreview.show(iframeRef, noteref)) return;

    const id = fragmentId(noteref.getAttribute("href"));
    if (id) {
      EpubInteraction.scrollToId(iframeRef, id);
    }
  }

  static scrollToId(
    iframeRef: RefObject<HTMLIFrameElement | null>,
    id: string,
  ) {
    const { current: iframe } = iframeRef;
    FootnotePreview.hide(iframeRef);
    if (iframe?.contentDocument && iframe?.contentWindow) {
      const element = iframe.contentDocument.getElementById(id);
      if (element) {
        const elementLeft = element.getBoundingClientRect().left;
        const currentScroll = iframe.contentWindow.scrollX;
        const absoluteLeft = elementLeft + currentScroll;
        const page = Math.floor(
          absoluteLeft / (iframe.clientWidth + COLUMN_GAP),
        );
        const scrollLeft = page * (iframe.clientWidth + COLUMN_GAP);

        iframe.contentWindow.scrollTo({
          left: scrollLeft,
          behavior: "instant",
        });
      }
    }
  }

  // onPastEnd is called instead of scrolling when a forward turn is asked for
  // on the last (or only) page
  static scrollPage(
    iframeRef: RefObject<HTMLIFrameElement | null>,
    direction: "forward" | "backward",
    onPastEnd?: () => void,
  ) {
    const { current: iframe } = iframeRef;
    FootnotePreview.hide(iframeRef);
    if (iframe?.contentWindow) {
      const scrollAmount = iframe.clientWidth + COLUMN_GAP;
      if (direction === "forward") {
        if (EpubInteraction.calculateReadingProgress(iframeRef).atEnd) {
          onPastEnd?.();
          return;
        }
        iframe.contentWindow.scrollBy({
          left: scrollAmount,
          behavior: "instant",
        });
      }
      if (direction === "backward") {
        iframe.contentWindow.scrollBy({
          left: -scrollAmount,
          behavior: "instant",
        });
      }
    }
  }

  static calculateReadingProgress(
    iframeRef: RefObject<HTMLIFrameElement | null>,
  ): ReadingProgress {
    const { current: iframe } = iframeRef;
    const out = { progress: 0, atEnd: false };
    if (iframe && iframe.contentWindow && iframe.contentDocument) {
      const scrollWidth = iframe.contentDocument.body.scrollWidth;
      const clientWidth = iframe.clientWidth;
      const scrollLeft = iframe.contentWindow.scrollX;

      if (scrollWidth > clientWidth) {
        out.progress = ReadingPosition.quantise(scrollLeft / scrollWidth);
        if (scrollLeft + clientWidth >= scrollWidth - 5) {
          out.atEnd = true;
        }
      } else {
        // if content fits in one screen, the whole document has been reached
        out.progress = 1;
        out.atEnd = true;
      }
    }
    return out;
  }

  static createEndTracking(): EndTracking {
    return { wasAtEnd: false };
  }

  // decides whether this scroll should mark the newsletter as read. the end has
  // to be newly reached, so marking it unread by hand while sitting on the last
  // page isn't undone by the next scroll event
  static shouldMarkRead(
    endTrackingRef: RefObject<EndTracking | null>,
    progress: ReadingProgress,
  ): boolean {
    const tracking = endTrackingRef.current;
    if (!tracking) return false;

    const newlyAtEnd = progress.atEnd && !tracking.wasAtEnd;
    tracking.wasAtEnd = progress.atEnd;
    return newlyAtEnd;
  }
}
