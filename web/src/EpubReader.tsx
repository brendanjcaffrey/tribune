import React, { useEffect, useRef } from "react";
import { useWindowHeight } from "@react-hook/window-size";
import ePub, { Book, Rendition } from "epubjs";

type Props = {
  file: ArrayBuffer;
};

const TOP_BAR_HEIGHT = 64;
const VERTICAL_PADDING = 16;
const CONTROLS_HEIGHT = 40;

const EpubReader: React.FC<Props> = ({ file }) => {
  const viewerRef = useRef<HTMLDivElement>(null);
  const renditionRef = useRef<Rendition | null>(null);
  const bookRef = useRef<Book | null>(null);
  const windowHeight = useWindowHeight();
  const totalHeight = windowHeight - TOP_BAR_HEIGHT - VERTICAL_PADDING * 2;
  const readerHeight = totalHeight - CONTROLS_HEIGHT;

  useEffect(() => {
    if (!viewerRef.current) return;

    const book = ePub(file);
    const rendition = book.renderTo(viewerRef.current, {
      width: "100%",
      height: "100%",
    });
    rendition.display();

    bookRef.current = book;
    renditionRef.current = rendition;

    return () => {
      rendition.destroy();
      book.destroy();
    };
  }, [file]);

  const goNext = () => renditionRef.current?.next();
  const goPrev = () => renditionRef.current?.prev();

  return (
    <div
      style={{
        height: `${totalHeight}px`,
        width: "100%",
        paddingTop: `${VERTICAL_PADDING}px`,
      }}
    >
      <div
        ref={viewerRef}
        style={{ height: `${readerHeight}px`, width: "100%" }}
      />
      <div>
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
