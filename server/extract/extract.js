// reads a page's html on stdin & writes the readable article to stdout as json.
//
//   node extract.js https://example.com/article < page.html
//   => {"title":"...","author":"...","content":"<div>...</div>"}
//
// this is the extraction half of server/article_extractor.rb, which is what
// calls it. it lives in node because @mozilla/readability is the same extractor
// firefox reader mode uses, and it keeps far more of the article (images,
// headings, tables, lists) than the ruby ports do.

const { Readability } = require("@mozilla/readability");
const { JSDOM, VirtualConsole } = require("jsdom");

// the epub only renders these, and anything else (data-*, aria-*, framework
// attributes like @click) is either dead weight or an invalid xml attribute
// name that would blow up the serializer below
const KEEP_ATTRIBUTES = new Set(["src", "href", "alt", "title"]);

// readability rewrites a single cell table into a paragraph, so these are only
// kept where they still mean something
const KEEP_ATTRIBUTES_BY_TAG = {
  td: ["colspan", "rowspan"],
  th: ["colspan", "rowspan"],
};

// readability leaves some of these behind (youtube iframes, mainly). none of
// them do anything in an epub reader, so they'd just render as a blank hole
const DROP_TAGS = [
  "audio",
  "button",
  "canvas",
  "embed",
  "form",
  "iframe",
  "input",
  "noscript",
  "object",
  "script",
  "select",
  "style",
  "svg",
  "textarea",
  "video",
];

// epub.rb has to fetch every image it packs, so a src it can't fetch (data:,
// blob:, mailto: & friends) is dropped here rather than half way through the
// epub build. readability has already made the rest absolute against the page url.
function isFetchable(src) {
  return /^https?:\/\//i.test(src || "");
}

function keeps(el, name) {
  const tag = el.tagName.toLowerCase();
  return (
    KEEP_ATTRIBUTES.has(name) ||
    (KEEP_ATTRIBUTES_BY_TAG[tag] || []).includes(name)
  );
}

// a lazy loading page can be most of the way through its article before a real
// src shows up, and dropping those images leaves a run of blank paragraphs
function isEmptyWrapper(el) {
  return (
    !el.textContent.trim() && !el.querySelector("img, br, hr, table, ul, ol")
  );
}

// a newsletter is mostly tracking pixels by count. packing them would mean
// downloading them, which is the read receipt they were after in the first place
function isTrackingPixel(img) {
  return ["width", "height"].some((dimension) => {
    const value = parseInt(img.getAttribute(dimension), 10);
    return !Number.isNaN(value) && value <= 2;
  });
}

function clean(root) {
  root.querySelectorAll(DROP_TAGS.join(",")).forEach((el) => el.remove());
  root.querySelectorAll("img").forEach((img) => {
    if (!isFetchable(img.getAttribute("src")) || isTrackingPixel(img)) {
      img.remove();
    }
  });
  root.querySelectorAll("p, figure, figcaption").forEach((el) => {
    if (isEmptyWrapper(el)) el.remove();
  });

  for (const el of [root, ...root.querySelectorAll("*")]) {
    for (const name of el.getAttributeNames()) {
      if (!keeps(el, name)) el.removeAttribute(name);
    }
  }
}

// epub.rb parses this back with Nokogiri::XML, so it gets xhtml (self closed
// void tags, escaped entities) rather than the html5 innerHTML would produce
function serialize(window, root) {
  clean(root);
  return new window.XMLSerializer().serializeToString(root);
}

function readStdin() {
  return new Promise((resolve, reject) => {
    const chunks = [];
    process.stdin.on("data", (chunk) => chunks.push(chunk));
    process.stdin.on("end", () =>
      resolve(Buffer.concat(chunks).toString("utf8")),
    );
    process.stdin.on("error", reject);
  });
}

async function main() {
  const url = process.argv[2];
  if (!url) throw new Error("usage: extract.js <url> < page.html");

  const html = await readStdin();
  if (!html.trim()) throw new Error("no html on stdin");

  // the console is silenced because jsdom is noisy about the css & js it can't
  // parse, and none of it matters when all we want is the text
  const dom = new JSDOM(html, { url, virtualConsole: new VirtualConsole() });
  const { window } = dom;

  const article = new Readability(window.document, {
    serializer: (root) => serialize(window, root),
  }).parse();

  // null means readability found nothing article shaped on the page. there's no
  // fallback worth having here: the alternative is packing the raw page,
  // boilerplate & all, into an epub
  if (!article) throw new Error(`no article content found at ${url}`);

  process.stdout.write(
    JSON.stringify({
      title: article.title || "",
      author: article.byline || "",
      content: article.content || "",
    }),
  );
}

main().catch((err) => {
  process.stderr.write(`${err.stack || err.message}\n`);
  process.exitCode = 1;
});
