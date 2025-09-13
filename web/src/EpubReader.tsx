import React, { useEffect, useRef } from "react";
import { useWindowSize } from "@react-hook/window-size";
import ePub, { Book, Rendition } from "epubjs";
import { Theme, useTheme } from "@mui/material";

type Props = {
  file: ArrayBuffer;
};

const TOP_BAR_HEIGHT = 64;
const VERTICAL_PADDING = 16;
const CONTROLS_HEIGHT = 40;

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

function totalHeight(windowHeight: number) {
  return windowHeight - TOP_BAR_HEIGHT - VERTICAL_PADDING;
}

function readerHeight(windowHeight: number) {
  return totalHeight(windowHeight) - CONTROLS_HEIGHT;
}

const EpubReader: React.FC<Props> = ({ file }) => {
  const theme = useTheme();
  const viewerRef = useRef<HTMLDivElement>(null);
  const renditionRef = useRef<Rendition | null>(null);
  const bookRef = useRef<Book | null>(null);
  const [windowWidth, windowHeight] = useWindowSize();

  useEffect(() => {
    if (renditionRef.current) {
      renditionRef.current.resize(windowWidth, readerHeight(windowHeight));
    }
  }, [windowHeight, windowWidth]);

  useEffect(() => {
    if (!viewerRef.current) return;

    const book = ePub(file);
    bookRef.current = book;

    const rendition = book.renderTo(viewerRef.current, {
      width: "100%",
      height: "100%",
    });
    setTheme(rendition, theme);
    rendition.display();
    renditionRef.current = rendition;

    return () => {
      rendition.destroy();
      book.destroy();
      renditionRef.current = null;
    };
  }, [file]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (renditionRef.current) {
      setTheme(renditionRef.current, theme);
    }
  }, [theme, renditionRef]);

  const goNext = () => renditionRef.current?.next();
  const goPrev = () => renditionRef.current?.prev();

  return (
    <div
      style={{
        height: `${totalHeight(windowHeight)}px`,
        width: "100%",
        paddingTop: `${VERTICAL_PADDING}px`,
      }}
    >
      <div
        ref={viewerRef}
        style={{
          height: `${readerHeight(windowHeight)}px`,
          width: `${windowWidth}px`,
        }}
      />
      <div
        style={{
          paddingTop: `${VERTICAL_PADDING}px`,
        }}
      >
        <button onClick={goPrev} className="px-3 py-1 bg-gray-200 rounded">
          ◀ Prev
        </button>
        <button onClick={goNext} className="px-3 py-1 bg-gray-200 rounded">
          Next ▶
        </button>
      </div>
    </div>
  );
};

export default EpubReader;
