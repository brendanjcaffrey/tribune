import React, { useEffect, useRef } from "react";
import { useWindowSize } from "@react-hook/window-size";
import ePub, { Book, Location, Rendition } from "epubjs";
import { Theme, useTheme } from "@mui/material";
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
      fontFamily: `${theme.typography.body1.fontFamily} !important`,
      fontSize: `${theme.typography.body1.fontSize} !important`,
      lineHeight: `${theme.typography.body1.lineHeight} !important`,
      margin: `${theme.spacing(2)} !important`,
      padding: `${theme.spacing(1)} !important`,
    },
    h1: {
      fontFamily: `${theme.typography.h1.fontFamily} !important`,
      fontSize: `${theme.typography.h1.fontSize} !important`,
      fontWeight: `${theme.typography.h1.fontWeight} !important`,
      lineHeight: `${theme.typography.h1.lineHeight} !important`,
    },
    h2: {
      fontFamily: `${theme.typography.h2.fontFamily} !important`,
      fontSize: `${theme.typography.h2.fontSize} !important`,
      fontWeight: `${theme.typography.h2.fontWeight} !important`,
      lineHeight: `${theme.typography.h2.lineHeight} !important`,
    },
    a: {
      color: `${theme.palette.primary.main} !important`,
      textDecoration: "none",
    },
    p: {
      marginBottom: theme.spacing(2),
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
  const [windowWidth, windowHeight] = useWindowSize();

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

    rendition.on("relocated", (location: Location) => {
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
  }, [file, closeFile]); // eslint-disable-line react-hooks/exhaustive-deps

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
          height: `${GetBodyHeight(windowHeight) - VERTICAL_PADDING * 2}px`,
          width: `${windowWidth}px`,
        }}
      />
    </div>
  );
};

export default EpubReader;
