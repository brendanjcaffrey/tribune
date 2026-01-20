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
  targetIsAnchor: boolean;
}

export interface ReadingProgress {
  progress: number;
  atEnd: boolean;
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

export class Cfi {
  static getElementCfiPath(element: Element | null): string {
    if (!element || element.tagName.toLowerCase() === "html") {
      return "/4";
    }
    if (element.tagName.toLowerCase() === "body") {
      return "/4";
    }

    let path = "";
    let current: Element | null = element;

    while (current && current.tagName.toLowerCase() !== "body") {
      if (!current.parentElement) {
        break;
      }
      const siblingIndex = Array.from(current.parentElement.children).indexOf(
        current,
      );
      const cfiIndex = (siblingIndex + 1) * 2;
      path = `/${cfiIndex}${path}`;
      current = current.parentElement;
    }

    return "/4" + path;
  }

  static getElementByCfiPath(doc: Document, cfiPath: string): Element | null {
    // remove the initial 4/ which corresponds to the <body> element in our CFI generation
    const cleanPath = cfiPath.startsWith("4/") ? cfiPath.substring(2) : cfiPath;
    const parts = cleanPath.split("/").filter(Boolean);
    let currentElement: Element | null = doc.body;

    for (const part of parts) {
      if (!currentElement || !currentElement.children) {
        return null;
      }
      const index = parseInt(part, 10);
      if (isNaN(index)) {
        return null;
      }

      const children: Element[] = Array.from(currentElement.children);
      const childIndex = index / 2 - 1;

      if (childIndex >= 0 && childIndex < children.length) {
        currentElement = children[childIndex];
      } else {
        return null;
      }
    }
    return currentElement;
  }

  static calculateCurrentCfi(
    iframeRef: RefObject<HTMLIFrameElement | null>,
  ): string | null {
    const { current: iframe } = iframeRef;
    if (iframe && iframe.contentWindow && iframe.contentDocument) {
      const range = iframe.contentDocument.caretPositionFromPoint(1, 1);
      const node = range ? range.offsetNode : null;
      const element =
        node && node.nodeType === 3 ? node.parentElement : (node as Element);
      const path = Cfi.getElementCfiPath(element);
      return `epubcfi(/6/2!${path})`;
    }
    return null;
  }

  static scrollToCfi(
    iframeRef: RefObject<HTMLIFrameElement | null>,
    cfi: string,
  ) {
    const { current: iframe } = iframeRef;
    // extract the path part, e.g., epubcfi(/6/2!/4/2/2/2/2/1:0 -> /4/2/2/2/2/1
    const cfiPathMatch = cfi.match(/!\/(.*?)(?::|$)/);
    if (
      cfiPathMatch &&
      iframe &&
      iframe.contentDocument &&
      iframe.contentWindow
    ) {
      const cfiPath = cfiPathMatch[1];
      const targetElement = Cfi.getElementByCfiPath(
        iframe.contentDocument,
        cfiPath,
      );

      if (targetElement) {
        const elementLeft = targetElement.getBoundingClientRect().left;
        const currentScroll = iframe.contentWindow.scrollX;
        const absoluteLeft = elementLeft + currentScroll;
        const pageWidth = iframe.clientWidth + COLUMN_GAP;
        const page = Math.floor(absoluteLeft / pageWidth);
        const scrollLeft = page * pageWidth;

        iframe.contentWindow.scrollTo({
          left: scrollLeft,
          behavior: "instant",
        });
      }
    }
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
        if (href) {
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
                }
                img {
                  max-width: 100%;
                  height: auto;
                }
                #__blank_epub_column {
                  display: inline-block;
                  height: 1px;
                  /* make sure it doesn't visibly affect layout other than occupying a column */
                  break-inside: avoid;
                }
                ${muiStyles}
                ${bookContent?.headContent}
              </style>
            </head>
            <body>
              ${bookContent?.bodyContent}
            </body>
          </html>
        `;
  }
}

// some of these interfaces may look a little strange, but this code is used
// by both the typescript/react web app and a plain javascript webview in the
// ios app, so some indirection is needed
export class EpubInteraction {
  static handleKeyDown(
    iframeRef: RefObject<HTMLIFrameElement | null>,
    event: KeyboardEvent,
    closeNewsletter: () => void,
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
      EpubInteraction.scrollPage(iframeRef, "forward");
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
        targetIsAnchor: (event.target as HTMLElement).closest("a") != null,
      };
    }
  }

  static handleTouchEnd(
    iframeRef: RefObject<HTMLIFrameElement | null>,
    touchStartRef: RefObject<TouchStart | null>,
    event: TouchEvent,
  ) {
    if (touchStartRef.current && event.changedTouches.length === 1) {
      const touchEndX = event.changedTouches[0].clientX;
      const touchStartX = touchStartRef.current.x;
      const deltaX = touchEndX - touchStartX;

      if (Math.abs(deltaX) >= SWIPE_THRESHOLD) {
        EpubInteraction.scrollPage(
          iframeRef,
          deltaX < 0 ? "forward" : "backward",
        );
      } else {
        if (touchStartRef.current.targetIsAnchor) {
          // nop, let the link work normally
        } else if (iframeRef.current?.contentWindow) {
          const screenWidth = iframeRef.current.clientWidth;
          EpubInteraction.scrollPage(
            iframeRef,
            touchEndX < screenWidth / 2 ? "backward" : "forward",
          );
        }
      }
      touchStartRef.current = null;
    }
  }

  static handleScrollToHref(
    iframeRef: RefObject<HTMLIFrameElement | null>,
    event: Event,
  ) {
    const { current: iframe } = iframeRef;
    const id = (event as CustomEvent).detail.href.substring(1);
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

  static scrollPage(
    iframeRef: RefObject<HTMLIFrameElement | null>,
    direction: "forward" | "backward",
  ) {
    const { current: iframe } = iframeRef;
    if (iframe?.contentWindow) {
      const scrollAmount = iframe.clientWidth + COLUMN_GAP;
      if (direction === "forward") {
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
        const progress = (scrollLeft / scrollWidth) * 100;
        out.progress = Math.round(progress);
        if (scrollLeft + clientWidth >= scrollWidth - 5) {
          out.atEnd = true;
        }
      } else {
        // if content fits in one screen, it's 100% read
        out.progress = 100;
        out.atEnd = true;
      }
    }
    return out;
  }
}
