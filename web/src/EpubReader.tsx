import {
  useEffect,
  useMemo,
  useState,
  useRef,
  useLayoutEffect,
  useCallback,
} from "react";
import { useWindowSize } from "@react-hook/window-size";
import { useColorScheme } from "./useColorScheme";
import { readThemeColors, type ThemeColors } from "./Theme";
import { Newsletter } from "./Library";
import {
  Epub,
  SpineItem,
  Cfi,
  COLUMN_GAP,
  TouchStart,
  EpubInteraction,
} from "./Epub";
import { WorkerInstance } from "./WorkerInstance";
import { buildMainMessage } from "./WorkerTypes";

const READER_FONT_FAMILY = '"Helvetica Neue", Helvetica, Arial, sans-serif';

// bootstrap has no js-readable typography scale, so define one for the epub
// iframe. colors come from the active bootstrap theme's css variables.
function getReaderStyles(colors: ThemeColors): string {
  return `
    body {
      background: ${colors.bodyBg} !important;
      color: ${colors.bodyColor} !important;
      font-family: ${READER_FONT_FAMILY} !important;
      font-size: 1rem !important;
      line-height: 1.5 !important;
    }
    h1 {
      font-family: ${READER_FONT_FAMILY} !important;
      font-size: 2.5rem !important;
      font-weight: 400 !important;
      line-height: 1.2 !important;
    }
    h2 {
      font-family: ${READER_FONT_FAMILY} !important;
      font-size: 2rem !important;
      font-weight: 400 !important;
      line-height: 1.2 !important;
    }
    h3 {
      font-family: ${READER_FONT_FAMILY} !important;
      font-size: 1.5rem !important;
      font-weight: 400 !important;
      line-height: 1.3 !important;
    }
    a {
      color: ${colors.primary} !important;
      text-decoration: none;
    }
    p {
      margin-bottom: 1rem;
    }
  `;
}

const FRAME_TITLEBAR_HEIGHT = 64;
const TWO_COLUMN_MIN_WIDTH = 800;
const VERTICAL_PADDING = 20;
const HORIZONTAL_PADDING = 40;
const PROGRESS_HEIGHT = 20;
const SPACER_ID = "__blank_epub_column";

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

const EpubReader: React.FC<EpubReaderProps> = ({
  newsletter,
  file,
  closeNewsletter,
}) => {
  const colorScheme = useColorScheme();
  // colorScheme drives the re-read of the dom css vars, which the linter can't see
  const colors = useMemo(() => readThemeColors(), [colorScheme]); // eslint-disable-line react-hooks/exhaustive-deps
  const [windowWidth, windowHeight] = useWindowSize();
  const [bookContent, setBookContent] = useState<SpineItem | null>(null);
  const [iframeContent, setIframeContent] = useState("");
  const [readingProgress, setReadingProgress] = useState(0);

  const iframeRef = useRef<HTMLIFrameElement>(null);
  const touchStartRef = useRef<TouchStart>(null);
  const setOffsetOnNextLoad = useRef<number | string | null>(null);

  // event handlers
  const handleKeyDown = useCallback(
    (event: KeyboardEvent) => {
      EpubInteraction.handleKeyDown(iframeRef, event, closeNewsletter);
    },
    [closeNewsletter],
  );

  const handleTouchStart = useCallback((event: TouchEvent) => {
    EpubInteraction.handleTouchStart(touchStartRef, event);
  }, []);

  const handleTouchEnd = useCallback((event: TouchEvent) => {
    EpubInteraction.handleTouchEnd(iframeRef, touchStartRef, event);
  }, []);

  const handleScrollToHref = useCallback((e: Event) => {
    EpubInteraction.handleScrollToHref(iframeRef, e);
  }, []);

  const updateReadingProgress = useCallback(() => {
    const progress = EpubInteraction.calculateReadingProgress(iframeRef);
    setReadingProgress(progress.progress);
    if (progress.atEnd) {
      WorkerInstance.postMessage(
        buildMainMessage("mark newsletter as read", {
          id: newsletter.id,
        }),
      );
    }
  }, [newsletter.id]);

  const saveProgress = useCallback(() => {
    const fullCfi = Cfi.calculateCurrentCfi(iframeRef);
    if (fullCfi) {
      WorkerInstance.postMessage(
        buildMainMessage("update newsletter progress", {
          id: newsletter.id,
          progress: fullCfi,
        }),
      );
    }

    updateReadingProgress();
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
        setBookContent(await epub.getSpineItem(0, "target _blank"));
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

    const content = Epub.buildIframeContent(
      CalculateColumnWidth(windowWidth),
      getReaderStyles(colors),
      bookContent,
      80,
    );
    setIframeContent(content);
  }, [bookContent, windowWidth, windowHeight, colors]);

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
          Cfi.scrollToCfi(iframeRef, setOffsetOnNextLoad.current);
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
          // content-box so the width excludes padding, which the column-count
          // math relies on; bootstrap's reboot sets border-box globally
          boxSizing: "content-box",
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
          boxSizing: "content-box",
          height: `${PROGRESS_HEIGHT}px`,
          width: `${windowWidth - HORIZONTAL_PADDING * 2}px`,
          textAlign: "right",
          padding: `0px ${HORIZONTAL_PADDING}px 0px`,
          background: colors.bodyBg,
          color: colors.bodyColor,
          fontFamily: READER_FONT_FAMILY,
          fontSize: "1rem",
          lineHeight: 1.5,
        }}
      >
        {readingProgress}%
      </div>
    </>
  );
};

export default EpubReader;
