const HORIZONTAL_PADDING = 10;
const COLUMN_GAP = 20;
const PROGRESS_HEIGHT = 20;
const VERTICAL_PADDING = 20;
const SWIPE_THRESHOLD = 50;

let iframeRef = { current: null };
let touchStartRef = { current: null };

function getMuiStyles(theme) {
  return `
    html {
      background: ${theme.palette.background.default} !important;
    }
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
    a[epub_type] {
      padding: 10px;
      margin: -10px;
      display: inline-block;
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
  const backgroundColor = theme.palette.background.default;
  const iframeContent = Bundle.Epub.buildIframeContent(
    calculateColumnWidth(window.innerWidth),
    getMuiStyles(theme),
    spineItem,
    100,
  );
  const iframeContentBlob = new Blob([iframeContent], { type: "text/html" });
  const iframeBlobUrl = URL.createObjectURL(iframeContentBlob);
  const styledContent = `
          <html>
            <head>
              <style>
                /* paint the theme background on every layer up front so there's
                   no white flash while the blob iframe loads in dark mode */
                html,
                body {
                  margin: 0;
                  background-color: ${backgroundColor};
                }
                #container {
                  height: ${window.innerHeight - VERTICAL_PADDING * 2 - PROGRESS_HEIGHT}px;
                  width: ${window.innerWidth - HORIZONTAL_PADDING * 2}px;
                  overflow: hidden;
                  padding: ${VERTICAL_PADDING}px ${HORIZONTAL_PADDING}px 0px;
                  background-color: ${backgroundColor};
                }
                #footer {
                  height: ${PROGRESS_HEIGHT}px;
                  width: ${window.innerWidth - HORIZONTAL_PADDING * 2}px;
                  padding: 0px ${HORIZONTAL_PADDING}px ${VERTICAL_PADDING}px;
                  text-align: left;
                }
                iframe {
                  width: 100%;
                  height: 100%;
                  border: none;
                  background-color: ${backgroundColor};
                  /* stay transparent until we've loaded and jumped to the saved
                     position, so the reader never flashes page one first. the
                     dark #container shows behind it in the meantime. opacity
                     (not visibility) keeps the iframe laid out so the seek can
                     measure element positions correctly. */
                  opacity: 0;
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
              </div>
            </body>
          </html>
        `;
  document.open();
  document.write(styledContent);
  document.close();
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

  const iframe = document.getElementsByTagName("iframe")[0];
  iframeRef.current = iframe;

  let listenersAttached = false;
  const attachContentListeners = () => {
    if (listenersAttached) return;
    listenersAttached = true;
    iframe.contentWindow.addEventListener("scroll", handleScroll);
    iframe.contentWindow.addEventListener("touchstart", handleTouchStart);
    iframe.contentWindow.addEventListener("touchend", handleTouchEnd);
    iframe.contentWindow.addEventListener("keydown", handleKeyDown);
  };

  // wire up the content window, restore the saved position, then fade the
  // iframe in. safe to run more than once - the listener guard plus the instant
  // scroll make it idempotent.
  let shown = false;
  const seekAndReveal = () => {
    attachContentListeners();
    if (initialProgress !== null) {
      Bundle.Cfi.scrollToCfi(iframeRef, initialProgress);
    }
    handleScroll();
    iframe.style.opacity = "1";
    shown = true;
  };

  // reveal as soon as the document has paginated instead of waiting on the load
  // event, which blocks until every image finishes. poll with rAF (no fixed
  // delay) until the content spills past a single screen, then seek and show.
  // waiting for scrollWidth > clientWidth matters: while it still fits one
  // screen calculateReadingProgress reports 100% / at-end and would mark the
  // newsletter read. genuinely short items that never paginate fall through to
  // the load backstop below, which marks them read as before.
  const showWhenLaidOut = () => {
    if (shown) return;
    const doc = iframe.contentDocument;
    if (doc && doc.body && doc.body.scrollWidth > iframe.clientWidth) {
      seekAndReveal();
    } else {
      requestAnimationFrame(showWhenLaidOut);
    }
  };
  requestAnimationFrame(showWhenLaidOut);

  // images can reflow the layout after they load, so seek once more when
  // everything is done to snap to the exact saved page. this also backstops the
  // reveal in case the rAF poll never sees a laid-out body.
  iframe.addEventListener("load", seekAndReveal);
}
