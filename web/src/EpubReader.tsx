import { useEffect, useRef, useState } from "react";
import { useWindowSize } from "@react-hook/window-size";
import { Theme, useTheme } from "@mui/material/styles";
import ePub, { Book, Location, Rendition } from "epubjs";
import { GetBodyHeight } from "./Height";
import { WorkerInstance } from "./WorkerInstance";
import { buildMainMessage } from "./WorkerTypes";
import { Newsletter } from "./Library";

type EpubReaderProps = {
  newsletter: Newsletter;
  file: ArrayBuffer;
  closeNewsletter: () => void;
};

const VERTICAL_PADDING = 16;

function setTheme(rendition: Rendition, theme: Theme) {
  // for whatever reason, epubjs doesn't seem to actually change anything if you select a
  // theme you had selected previously, so we have to use a random name here for a dark->light->dark
  // switch to work
  const randomString = Math.random().toString(36).substring(2, 15);
  rendition.themes.register(randomString, {
    body: {
      background: `${theme.palette.background.default} !important`,
      color: `${theme.palette.text.primary} !important`,
      "font-family": `${theme.typography.body1.fontFamily} !important`,
      "font-size": `${theme.typography.body1.fontSize} !important`,
      "line-height": `${theme.typography.body1.lineHeight} !important`,
      margin: `${theme.spacing(2)} !important`,
      padding: `${theme.spacing(1)} !important`,
    },
    h1: {
      "font-family": `${theme.typography.h3.fontFamily} !important`,
      "font-size": `${theme.typography.h3.fontSize} !important`,
      "font-weight": `${theme.typography.h3.fontWeight} !important`,
      "line-height": `${theme.typography.h3.lineHeight} !important`,
    },
    h2: {
      "font-family": `${theme.typography.h4.fontFamily} !important`,
      "font-size": `${theme.typography.h4.fontSize} !important`,
      "font-weight": `${theme.typography.h4.fontWeight} !important`,
      "line-height": `${theme.typography.h4.lineHeight} !important`,
    },
    h3: {
      "font-family": `${theme.typography.h5.fontFamily} !important`,
      "font-size": `${theme.typography.h5.fontSize} !important`,
      "font-weight": `${theme.typography.h5.fontWeight} !important`,
      "line-height": `${theme.typography.h5.lineHeight} !important`,
    },
    a: {
      color: `${theme.palette.primary.main} !important`,
      "text-decoration": "none",
    },
    p: {
      "margin-bottom": theme.spacing(2),
    },
  });
  rendition.themes.select(randomString);
}

function buildKeyHandler(rendition: Rendition, closeFile: () => void) {
  return (e: KeyboardEvent) => {
    const tag = (e.target as HTMLElement)?.tagName?.toLowerCase();
    if (
      tag === "input" ||
      tag === "textarea" ||
      (e.target as HTMLElement)?.isContentEditable
    ) {
      return;
    }

    switch (e.key) {
      case "ArrowRight":
        e.preventDefault();
        rendition.next();
        break;
      case "ArrowLeft":
        e.preventDefault();
        rendition.prev();
        break;
      case "Escape":
        e.preventDefault();
        closeFile();
        break;
    }
  };
}

const EpubReader: React.FC<EpubReaderProps> = ({
  newsletter,
  file,
  closeNewsletter: closeFile,
}) => {
  const theme = useTheme();
  const viewerRef = useRef<HTMLDivElement>(null);
  const renditionRef = useRef<Rendition | null>(null);
  const bookRef = useRef<Book | null>(null);
  const cfiRef = useRef<string | null>(null);
  const [windowWidth, windowHeight] = useWindowSize();
  const [percentage, setPercentage] = useState(0);

  const updatePercentage = () => {
    if (bookRef.current && cfiRef.current) {
      const percentage = bookRef.current.locations.percentageFromCfi(
        cfiRef.current,
      );
      setPercentage(
        percentage === undefined ? 0 : Math.floor(percentage * 100),
      );
    } else {
      setPercentage(0);
    }
  };

  useEffect(() => {
    if (renditionRef.current) {
      renditionRef.current.resize(
        windowWidth,
        GetBodyHeight(windowHeight) - VERTICAL_PADDING * 2,
      );
    }
  }, [windowHeight, windowWidth]);

  useEffect(() => {
    if (!viewerRef.current) {
      return;
    }

    const book = ePub(file);
    bookRef.current = book;

    book.ready.then(() => {
      book.locations.generate(150).then(() => {
        updatePercentage();
      });
    });

    const rendition = book.renderTo(viewerRef.current, {
      width: "100%",
      height: "100%",
      allowPopups: true,
      // NB: the typings are wrong here; allowPopups exists, so cast to any to fix the build
    } as any); // eslint-disable-line @typescript-eslint/no-explicit-any
    setTheme(rendition, theme);
    if (newsletter.progress.length > 0) {
      rendition.display(newsletter.progress);
    } else {
      rendition.display();
    }
    renditionRef.current = rendition;

    const handleKey = buildKeyHandler(rendition, closeFile);
    rendition.on("keydown", handleKey);
    window.addEventListener("keydown", handleKey);

    let startX = 0;
    const handleTouchStart = (e: TouchEvent) => {
      startX = e.changedTouches[0].screenX;
    };

    const handleTouchEnd = (e: TouchEvent) => {
      const endX = e.changedTouches[0].screenX;
      const deltaX = endX - startX;
      const threshold = 50; // px threshold to count as swipe

      if (Math.abs(deltaX) > threshold) {
        if (deltaX < 0) {
          rendition.next();
        } else {
          rendition.prev();
        }
      } else {
        if (startX < window.innerWidth / 2) {
          rendition.prev();
        } else {
          rendition.next();
        }
      }
    };

    rendition.on("touchstart", handleTouchStart);
    rendition.on("touchend", handleTouchEnd);

    rendition.on("relocated", (location: Location) => {
      cfiRef.current = location.start.cfi;
      updatePercentage();
      WorkerInstance.postMessage(
        buildMainMessage("update newsletter progress", {
          id: newsletter.id,
          progress: location.start.cfi,
        }),
      );
      if (location.atEnd) {
        WorkerInstance.postMessage(
          buildMainMessage("mark newsletter as read", {
            id: newsletter.id,
          }),
        );
      }
    });

    viewerRef.current.setAttribute("tabindex", "0");
    viewerRef.current.focus();

    return () => {
      rendition.destroy();
      book.destroy();
      renditionRef.current = null;
      window.removeEventListener("keydown", handleKey);
    };
  }, [file, closeFile, setPercentage]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (renditionRef.current) {
      setTheme(renditionRef.current, theme);
    }
  }, [theme, renditionRef]);

  return (
    <div
      style={{
        height: `${GetBodyHeight(windowHeight)}px`,
        width: "100%",
        paddingTop: `${VERTICAL_PADDING}px`,
        paddingBottom: `${VERTICAL_PADDING}px`,
      }}
    >
      <div
        ref={viewerRef}
        style={{
          height: `${GetBodyHeight(windowHeight) - VERTICAL_PADDING * 3}px`,
          width: `${windowWidth}px`,
        }}
      />
      <div
        style={{
          height: `${VERTICAL_PADDING}px`,
          width: `${windowWidth - 12}px`,
          textAlign: "right",
        }}
      >
        {percentage}%
      </div>
    </div>
  );
};

export default EpubReader;
