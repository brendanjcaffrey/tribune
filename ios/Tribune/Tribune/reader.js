const HORIZONTAL_PADDING = 10;
const COLUMN_GAP = 20;
const PROGRESS_HEIGHT = 20;
const VERTICAL_PADDING = 20;
const SWIPE_THRESHOLD = 50;

let iframeRef = { current: null };
let touchStartRef = { current: null };

function getMuiStyles(theme) {
  return `
    body {
      background: ${theme.palette.background.default} !important;
      color: ${theme.palette.text.primary} !important;
      font-family: Roboto, Helvetica, Arial, sans-serif !important;
      font-size: 1rem !important;
      line-height: 1.5 !important;
    }
    h1 {
      font-family: Roboto, Helvetica, Arial, sans-serif !important;
      font-size: 3rem !important;
      font-weight: 400 !important;
      line-height: 1.167 !important;
    }
    h2 {
      font-family: Roboto, Helvetica, Arial, sans-serif !important;
      font-size: 2.125rem !important;
      font-weight: 400 !important;
      line-height: 1.235 !important;
    }
    h3 {
      font-family: Roboto, Helvetica, Arial, sans-serif !important;
      font-size: 1.5rem !important;
      font-weight: 400 !important;
      line-height: 1.334 !important;
    }
    a {
      color: ${theme.palette.primary.main} !important;
      text-decoration: none;
    }
    p {
      margin-bottom: 16px;
    }
  `;
}

function calculateColumnWidth(windowWidth) {
  return windowWidth - HORIZONTAL_PADDING;
}

async function readLocalFileToArrayBuffer(url) {
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Fetch failed: ${res.status}`);
  }
  return await res.arrayBuffer();
}

function setContent(spineItem) {
  const theme =
    window.matchMedia &&
    window.matchMedia("(prefers-color-scheme: dark)").matches
      ? {
          palette: {
            background: { default: "#000000" },
            text: { primary: "#ffffff" },
            primary: { main: "#90caf9" },
          },
        }
      : {
          palette: {
            background: { default: "#ffffff" },
            text: { primary: "rgba(0, 0, 0, 0.87)" },
            primary: { main: "#1976d2" },
          },
        };
  const iframeContent = Bundle.Epub.buildIframeContent(
    calculateColumnWidth(window.innerWidth),
    getMuiStyles(theme),
    spineItem,
  );
  const iframeContentBlob = new Blob([iframeContent], { type: "text/html" });
  const iframeBlobUrl = URL.createObjectURL(iframeContentBlob);
  const styledContent = `
          <html>
            <head>
              <style>
                body {
                  margin: 0;
                }
                #container {
                  height: ${window.innerHeight - VERTICAL_PADDING * 2 - PROGRESS_HEIGHT}px;
                  width: ${window.innerWidth - HORIZONTAL_PADDING * 2}px;
                  overflow: hidden;
                  padding: ${VERTICAL_PADDING}px ${HORIZONTAL_PADDING}px 0px;
                }
                #footer {
                  height: ${PROGRESS_HEIGHT}px;
                  width: ${window.innerWidth - HORIZONTAL_PADDING * 2}px;
                  textAlign: right;
                  padding: 0px ${HORIZONTAL_PADDING}px ${VERTICAL_PADDING}px;
                  display: flex;
                  justify-content: space-between;
                  align-items: center;
                }
                #dismiss {
                  border: none;
                  background-color: transparent;
                  font-size: 20px;
                }
                iframe {
                  width: 100%;
                  height: 100%;
                  border: none;
                }
                ${getMuiStyles(theme)}
              </style>
            </head>
            <body>
              <div id="container">
                <iframe sandbox="allow-same-origin allow-scripts" src="${iframeBlobUrl}"></iframe>
              </div>
              <div id="footer">
                <span id="progress">&nbsp;</span>
                <button id="dismiss" onclick="dismiss()">X</button>
              </div>
            </body>
          </html>
        `;
  document.open();
  document.write(styledContent);
  document.close();
}

function dismiss() {
  window.webkit.messageHandlers.readerEvent.postMessage({ type: "dismiss" });
}

function handleKeyDown(event) {
  Bundle.EpubInteraction.handleKeyDown(iframeRef, event);
}

function handleTouchStart(event) {
  Bundle.EpubInteraction.handleTouchStart(touchStartRef, event);
}

function handleTouchEnd(event) {
  Bundle.EpubInteraction.handleTouchEnd(iframeRef, touchStartRef, event);
}

function handleScrollToHref(event) {
  Bundle.EpubInteraction.handleScrollToHref(iframeRef, event);
}

function handleOpenExternalLink(event) {
  window.webkit.messageHandlers.readerEvent.postMessage({
    type: "external link",
    href: event.detail.href,
  });
}

function handleScroll() {
  const cfi = Bundle.Cfi.calculateCurrentCfi(iframeRef);
  window.webkit.messageHandlers.readerEvent.postMessage({
    type: "progress",
    cfi: cfi,
  });

  const progress = Bundle.EpubInteraction.calculateReadingProgress(iframeRef);
  document.getElementById("progress").textContent =
    Math.round(progress.progress).toString() + "%";
  if (progress.atEnd) {
    window.webkit.messageHandlers.readerEvent.postMessage({
      type: "at end",
    });
  }
}

async function openBook(path, initialProgress) {
  const buf = await readLocalFileToArrayBuffer(path);
  book = new Bundle.Epub(buf);
  await book.parse();

  if (book.spine.length > 0) {
    const bookContent = await book.getSpineItem(0, "event");
    setContent(bookContent);
  }

  window.addEventListener("touchstart", handleTouchStart);
  window.addEventListener("touchend", handleTouchEnd);
  window.addEventListener("keydown", handleKeyDown);
  window.addEventListener("scrollToHref", handleScrollToHref);
  window.addEventListener("openExternalLink", handleOpenExternalLink);

  let iframe = document.getElementsByTagName("iframe")[0];
  iframeRef.current = iframe;
  iframe.contentWindow.addEventListener("scroll", handleScroll);
  iframe.contentWindow.addEventListener("touchstart", handleTouchStart);
  iframe.contentWindow.addEventListener("touchend", handleTouchEnd);
  iframe.contentWindow.addEventListener("keydown", handleKeyDown);

  if (initialProgress !== null) {
    setTimeout(() => Bundle.Cfi.scrollToCfi(iframeRef, initialProgress), 5);
  }
  setTimeout(() => handleScroll(), 50);
}
