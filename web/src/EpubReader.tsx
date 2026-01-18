import {
  useEffect,
  useState,
  useRef,
  useLayoutEffect,
  useCallback,
} from "react";
import { useWindowSize } from "@react-hook/window-size";
import { Theme, useTheme } from "@mui/material/styles";
import { Newsletter } from "./Library";
import { Epub, SpineItem } from "./Epub";
import { WorkerInstance } from "./WorkerInstance";
import { buildMainMessage } from "./WorkerTypes";

function getMuiStyles(theme: Theme): string {
  return `
    body {
      background: ${theme.palette.background.default} !important;
      color: ${theme.palette.text.primary} !important;
      font-family: ${theme.typography.body1.fontFamily} !important;
      font-size: ${theme.typography.body1.fontSize} !important;
      line-height: ${theme.typography.body1.lineHeight} !important;
    }
    h1 {
      font-family: ${theme.typography.h3.fontFamily} !important;
      font-size: ${theme.typography.h3.fontSize} !important;
      font-weight: ${theme.typography.h3.fontWeight} !important;
      line-height: ${theme.typography.h3.lineHeight} !important;
    }
    h2 {
      font-family: ${theme.typography.h4.fontFamily} !important;
      font-size: ${theme.typography.h4.fontSize} !important;
      font-weight: ${theme.typography.h4.fontWeight} !important;
      line-height: ${theme.typography.h4.lineHeight} !important;
    }
    h3 {
      font-family: ${theme.typography.h5.fontFamily} !important;
      font-size: ${theme.typography.h5.fontSize} !important;
      font-weight: ${theme.typography.h5.fontWeight} !important;
      line-height: ${theme.typography.h5.lineHeight} !important;
    }
    a {
      color: ${theme.palette.primary.main} !important;
      text-decoration: none;
    }
    p {
      margin-bottom: ${theme.spacing(2)};
    }
  `;
}

const FRAME_TITLEBAR_HEIGHT = 64;
const TWO_COLUMN_MIN_WIDTH = 800;
const VERTICAL_PADDING = 20;
const HORIZONTAL_PADDING = 40;
const PROGRESS_HEIGHT = 20;
const COLUMN_GAP = 40;
const SPACER_ID = "__blank_epub_column";
const SWIPE_THRESHOLD = 50;

function CalculateColumnWidth(windowWidth: number): number {
  if (windowWidth > TWO_COLUMN_MIN_WIDTH) {
    // this might look wrong but i promise it's not - we want two columns and only one gap on the screen
    return (windowWidth - HORIZONTAL_PADDING * 2 - COLUMN_GAP) / 2;
  } else {
    return windowWidth - HORIZONTAL_PADDING * 2;
  }
}

type EpubReaderProps = {
  newsletter: Newsletter;
  file: ArrayBuffer;
  closeNewsletter: () => void;
};

function GetElementCfiPath(element: Element | null): string {
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

function GetElementByCfiPath(doc: Document, cfiPath: string): Element | null {
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

function ScrollPage(
  iframe: HTMLIFrameElement | null,
  direction: "forward" | "backward",
) {
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

const EpubReader: React.FC<EpubReaderProps> = ({
  newsletter,
  file,
  closeNewsletter,
}) => {
  const theme = useTheme();
  const [windowWidth, windowHeight] = useWindowSize();
  const [bookContent, setBookContent] = useState<SpineItem | null>(null);
  const [iframeContent, setIframeContent] = useState("");
  const [readingProgress, setReadingProgress] = useState(0);

  const iframeRef = useRef<HTMLIFrameElement>(null);
  const touchStartRef = useRef<{
    x: number;
    y: number;
    targetIsNavAnchor: boolean;
  } | null>(null);
  const setOffsetOnNextLoad = useRef<number | string | null>(null);

  // event handlers
  const handleKeyDown = useCallback(
    (event: KeyboardEvent) => {
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
        ScrollPage(iframeRef.current, "forward");
      } else if (event.key === "ArrowLeft") {
        ScrollPage(iframeRef.current, "backward");
      }
    },
    [closeNewsletter],
  );

  const handleTouchStart = useCallback((event: TouchEvent) => {
    if (event.touches.length === 1) {
      touchStartRef.current = {
        x: event.touches[0].clientX,
        y: event.touches[0].clientY,
        targetIsNavAnchor:
          (event.target as HTMLElement).tagName.toLowerCase() === "a" &&
          (event.target as HTMLElement).hasAttribute("epub_type"),
      };
    }
  }, []);

  const handleTouchEnd = useCallback((event: TouchEvent) => {
    if (touchStartRef.current && event.changedTouches.length === 1) {
      const touchEndX = event.changedTouches[0].clientX;
      const touchStartX = touchStartRef.current.x;
      const deltaX = touchEndX - touchStartX;

      if (Math.abs(deltaX) >= SWIPE_THRESHOLD) {
        ScrollPage(iframeRef.current, deltaX < 0 ? "forward" : "backward");
      } else {
        if (touchStartRef.current.targetIsNavAnchor) {
          // nop, let the link work normally
        } else if (iframeRef.current?.contentWindow) {
          const screenWidth = iframeRef.current.clientWidth;
          ScrollPage(
            iframeRef.current,
            touchEndX < screenWidth / 2 ? "backward" : "forward",
          );
        }
      }
      touchStartRef.current = null;
    }
  }, []);

  const handleScrollToHref = useCallback((e: Event) => {
    const id = (e as CustomEvent).detail.href.substring(1);
    const { current: iframe } = iframeRef;
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
  }, []);

  const updateReadingProgress = useCallback(() => {
    const { current: iframe } = iframeRef;
    if (iframe && iframe.contentWindow && iframe.contentDocument) {
      const scrollWidth = iframe.contentDocument.body.scrollWidth;
      const clientWidth = iframe.clientWidth;
      const scrollLeft = iframe.contentWindow.scrollX;

      if (scrollWidth > clientWidth) {
        const progress = (scrollLeft / scrollWidth) * 100;
        setReadingProgress(Math.round(progress));
      } else {
        setReadingProgress(100); // if content fits in one screen, it's 100% read
      }

      // check if scrolled to the end
      // a small buffer is added to account for potential floating point inaccuracies
      if (scrollLeft + clientWidth >= scrollWidth - 5) {
        WorkerInstance.postMessage(
          buildMainMessage("mark newsletter as read", {
            id: newsletter.id,
          }),
        );
      }
    }
  }, [newsletter.id]);

  const saveProgress = useCallback(() => {
    const iframe = iframeRef.current;
    if (iframe && iframe.contentWindow && iframe.contentDocument) {
      const range = iframe.contentDocument.caretPositionFromPoint(1, 1);
      const node = range ? range.offsetNode : null;
      const element =
        node && node.nodeType === 3 ? node.parentElement : (node as Element);
      const path = GetElementCfiPath(element);
      const cfi = `epubcfi(/6/2!${path})`;

      WorkerInstance.postMessage(
        buildMainMessage("update newsletter progress", {
          id: newsletter.id,
          progress: cfi,
        }),
      );

      updateReadingProgress();
    }
  }, [newsletter.id, updateReadingProgress]);

  useEffect(() => {
    // these events are added when parsing the epub content
    window.addEventListener("scrollToHref", handleScrollToHref);
    return () => {
      window.removeEventListener("scrollToHref", handleScrollToHref);
    };
  }, [handleScrollToHref]);

  useEffect(() => {
    window.addEventListener("keydown", handleKeyDown);
    return () => {
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [handleKeyDown]);

  // parse epub on file change
  useEffect(() => {
    if (!file || file.byteLength === 0) {
      setBookContent(null);
      return;
    }

    const epub = new Epub(file);
    epub.parse().then(async () => {
      if (epub.spine.length > 0) {
        setBookContent(await epub.getSpineItem(0));
        if (newsletter.progress) {
          setOffsetOnNextLoad.current = newsletter.progress;
        }
      }
    });
  }, [file]); // eslint-disable-line react-hooks/exhaustive-deps

  // frame the book content - this is done as a separate step because the framing changes when the screen size does
  useEffect(() => {
    if (!bookContent) {
      setIframeContent("");
    }

    const styledContent = `
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

                  column-width: ${CalculateColumnWidth(windowWidth)}px;
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
                ${getMuiStyles(theme)}
                ${bookContent?.headContent}
              </style>
            </head>
            <body>
              ${bookContent?.bodyContent}
            </body>
          </html>
        `;
    setIframeContent(styledContent);
  }, [bookContent, windowWidth, windowHeight, theme]);

  useEffect(() => {
    const iframe = iframeRef.current;
    if (!iframe) return;

    const attachScrollListener = () => {
      const { current: iframe } = iframeRef;
      if (iframe && iframe.contentWindow) {
        iframe.contentWindow.addEventListener("scroll", saveProgress);
      }
    };

    // attach now and on load
    attachScrollListener();
    iframe.addEventListener("load", attachScrollListener);

    return () => {
      iframe.removeEventListener("load", attachScrollListener);
      iframe.contentWindow?.removeEventListener("scroll", saveProgress);
    };
  }, [newsletter.id, saveProgress]);

  useLayoutEffect(() => {
    const iframe = iframeRef.current;
    if (iframe && iframe.contentWindow) {
      // on resize, snap to the nearest page
      const page = Math.round(
        iframe.contentWindow.scrollX / (iframe.clientWidth + COLUMN_GAP),
      );
      const scrollLeft = page * (iframe.clientWidth + COLUMN_GAP);
      setOffsetOnNextLoad.current = scrollLeft;
    }
  }, [windowWidth, windowHeight]);

  const ensureEvenColumns = (windowWidth: number) => {
    if (windowWidth <= TWO_COLUMN_MIN_WIDTH) return; // only applies in two-column mode

    const iframe = iframeRef.current;
    if (!iframe || !iframe.contentDocument || !iframe.contentWindow) return;
    try {
      const body = iframe.contentDocument.body;
      // remove previous blank spacer if present
      const prev = iframe.contentDocument.getElementById(SPACER_ID);
      if (prev) prev.remove();

      const totalWidth = body.scrollWidth + COLUMN_GAP;
      const columnWidth = CalculateColumnWidth(windowWidth) + COLUMN_GAP;
      const pages = totalWidth / columnWidth;

      if (pages % 2 === 1) {
        const div = iframe.contentDocument.createElement("div");
        div.id = SPACER_ID;
        div.style.width = `${iframe.clientWidth}px`;
        body.appendChild(div);
      }
    } catch (e) {
      console.error(e);
    }
  };

  useEffect(() => {
    const iframe = iframeRef.current;
    if (!iframe) return;

    // have to attach after load or it won't work
    const onLoad = () => {
      iframe.contentDocument?.addEventListener("keydown", handleKeyDown);
      iframe.contentDocument?.addEventListener(
        "touchstart",
        handleTouchStart as EventListener,
      );
      iframe.contentDocument?.addEventListener(
        "touchend",
        handleTouchEnd as EventListener,
      );
      // ensure even number of columns on load
      ensureEvenColumns(windowWidth);

      if (setOffsetOnNextLoad.current !== null && iframe.contentWindow) {
        // check if the stored offset is a CFI string
        if (
          typeof setOffsetOnNextLoad.current === "string" &&
          setOffsetOnNextLoad.current.startsWith("epubcfi")
        ) {
          const cfiString = setOffsetOnNextLoad.current;
          // extract the path part, e.g., epubcfi(/6/2!/4/2/2/2/2/1:0 -> /4/2/2/2/2/1
          const cfiPathMatch = cfiString.match(/!\/(.*?)(?::|$)/);
          if (cfiPathMatch && iframe.contentDocument) {
            const cfiPath = cfiPathMatch[1];
            const targetElement = GetElementByCfiPath(
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
        } else if (typeof setOffsetOnNextLoad.current === "number") {
          iframe.contentWindow.scrollTo({
            left: setOffsetOnNextLoad.current,
            behavior: "instant",
          });
        }
        setOffsetOnNextLoad.current = null;
      }
    };
    iframe.addEventListener("load", onLoad);

    // attach in case contentDocument already exists
    iframe.contentDocument?.addEventListener("keydown", handleKeyDown);
    iframe.contentDocument?.addEventListener(
      "touchstart",
      handleTouchStart as EventListener,
    );
    iframe.contentDocument?.addEventListener(
      "touchend",
      handleTouchEnd as EventListener,
    );

    // also run now in case iframe is already loaded
    ensureEvenColumns(windowWidth);

    return () => {
      iframe.removeEventListener("load", onLoad);
      iframe.contentDocument?.removeEventListener("keydown", handleKeyDown);
      iframe.contentDocument?.removeEventListener(
        "touchstart",
        handleTouchStart as EventListener,
      );
      iframe.contentDocument?.removeEventListener(
        "touchend",
        handleTouchEnd as EventListener,
      );
      const prev = iframe.contentDocument?.getElementById(SPACER_ID);
      if (prev) prev.remove();
    };
  }, [
    handleKeyDown,
    windowWidth,
    windowHeight,
    iframeContent,
    handleTouchStart,
    handleTouchEnd,
  ]);

  return (
    <>
      <div
        style={{
          height: `${windowHeight - FRAME_TITLEBAR_HEIGHT - VERTICAL_PADDING * 2 - PROGRESS_HEIGHT}px`,
          width: `${windowWidth - HORIZONTAL_PADDING * 2}px`,
          overflow: "hidden",
          padding: `${VERTICAL_PADDING}px ${HORIZONTAL_PADDING}px 0px`,
        }}
      >
        <iframe
          ref={iframeRef}
          srcDoc={iframeContent}
          style={{ border: "none", height: "100%", width: "100%" }}
          title="epub-content"
          sandbox="allow-same-origin allow-popups allow-scripts"
        />
      </div>
      <div
        style={{
          height: `${PROGRESS_HEIGHT}px`,
          width: `${windowWidth - HORIZONTAL_PADDING * 2}px`,
          textAlign: "right",
          padding: `0px ${HORIZONTAL_PADDING}px 0px`,
          background: `${theme.palette.background.default} !important`,
          color: `${theme.palette.text.primary} !important`,
          fontFamily: `${theme.typography.body1.fontFamily} !important`,
          fontSize: `${theme.typography.body1.fontSize} !important`,
          lineHeight: `${theme.typography.body1.lineHeight} !important`,
        }}
      >
        {readingProgress}%
      </div>
    </>
  );
};

export default EpubReader;
