// reads the full-text-rss site config files (github.com/fivefilters/ftr-site-config)
// and applies them to a page. a site config is a per host list of xpaths saying
// where that site keeps its article, which beats guessing at it: readability has
// to infer the body from text density, whereas theguardian.com.txt just says
// //div[contains(@class, 'article-body')].
//
// only the directives that make sense here are acted on. the ones about
// fetching a page (http_header, requires_login, login_*, next_page_link,
// single_page_link) don't apply because the firefox extension sends us html it
// already has, logged in and all pages joined; tidy & prune name parsers and
// cleaners we don't run, and extract.js cleans the result its own way regardless.

const fs = require("fs");
const path = require("path");

// document.evaluate result types, from the dom spec
const ANY_TYPE = 0;
const STRING_TYPE = 2;
const UNORDERED_NODE_ITERATOR_TYPE = 4;
const ORDERED_NODE_ITERATOR_TYPE = 5;

const ATTRIBUTE_NODE = 2;
const ELEMENT_NODE = 1;

// directive name in the file -> the list it lands in here
const LISTS = {
  title: "titles",
  author: "authors",
  body: "bodies",
  strip: "strip",
  strip_id_or_class: "stripIdOrClass",
  strip_image_src: "stripImageSrc",
  strip_attr: "stripAttr",
};

function emptyConfig() {
  return {
    titles: [],
    authors: [],
    bodies: [],
    strip: [],
    stripIdOrClass: [],
    stripImageSrc: [],
    stripAttr: [],
    replacements: [],
    autodetectOnFailure: true,
  };
}

function normalize(value) {
  return String(value == null ? "" : value)
    .replace(/\s+/g, " ")
    .trim();
}

// the format is one `directive: value` per line, # for comments, and a directive
// may appear as many times as it likes
function parse(text) {
  const config = emptyConfig();
  const finds = [];

  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;

    const separator = trimmed.indexOf(":");
    if (separator === -1) continue;

    const key = trimmed.slice(0, separator).trim();
    const value = trimmed.slice(separator + 1).trim();
    const call = key.match(/^([a-z_]+)\((.*)\)$/);

    if (call && call[1] === "replace_string") {
      config.replacements.push({ find: call[2], replace: value });
    } else if (key === "find_string") {
      finds.push(value);
    } else if (key === "replace_string") {
      // find_string & replace_string are written as pairs of lines, so the nth
      // of one goes with the nth of the other
      if (finds.length)
        config.replacements.push({ find: finds.shift(), replace: value });
    } else if (key === "autodetect_on_failure") {
      config.autodetectOnFailure = value.toLowerCase() !== "no";
    } else if (LISTS[key] && value) {
      config[LISTS[key]].push(value);
    }
  }

  return config;
}

// the file for a host may be named for it exactly, or with a leading dot to
// cover every subdomain: .blogspot.com.txt is how one file serves all of them
function candidates(host) {
  const bare = host.replace(/^www\./, "");
  const names = [host, bare, `www.${bare}`];
  const labels = bare.split(".");

  // stop before the last two labels, so a page on example.com can't be handed
  // a config meant for every .com there is
  for (let i = 0; i + 2 <= labels.length; i++) {
    names.push(`.${labels.slice(i).join(".")}`);
  }

  return [...new Set(names)];
}

function read(dir, name) {
  try {
    return parse(fs.readFileSync(path.join(dir, `${name}.txt`), "utf8"));
  } catch {
    // there is no config for this host, which is the usual case
    return null;
  }
}

function hostname(url) {
  try {
    return new URL(url).hostname.toLowerCase();
  } catch {
    return null;
  }
}

// global.txt holds the directives that apply everywhere (open graph metadata,
// ad networks, amp tags). its title & author xpaths are kept apart from the
// site's own because they're a generic guess: readability's is usually better,
// and extract.js only falls back to these once it has run out of both.
function merge(site, global) {
  return {
    titles: site.titles,
    authors: site.authors,
    globalTitles: global.titles,
    globalAuthors: global.authors,
    bodies: site.bodies.concat(global.bodies),
    strip: site.strip.concat(global.strip),
    stripIdOrClass: site.stripIdOrClass.concat(global.stripIdOrClass),
    stripImageSrc: site.stripImageSrc.concat(global.stripImageSrc),
    stripAttr: site.stripAttr.concat(global.stripAttr),
    replacements: site.replacements.concat(global.replacements),
    autodetectOnFailure: site.autodetectOnFailure,
  };
}

function load(dir, url) {
  const host = dir ? hostname(url) : null;
  if (!host) return merge(emptyConfig(), emptyConfig());

  let site = null;
  for (const name of candidates(host)) {
    site = read(dir, name);
    if (site) break;
  }

  return merge(site || emptyConfig(), read(dir, "global") || emptyConfig());
}

// applied to the html as text, before it is parsed, which is the point of them:
// they exist for markup a parser would otherwise make the wrong shape out of
function replace(html, config) {
  return config.replacements.reduce(
    (text, { find, replace: to }) => (find ? text.split(find).join(to) : text),
    html,
  );
}

function quote(value) {
  if (!value.includes("'")) return `'${value}'`;
  if (!value.includes('"')) return `"${value}"`;
  return `concat('${value.split("'").join(`', "'", '`)}')`;
}

function query(document, xpath) {
  let result;
  try {
    result = document.evaluate(xpath, document, null, ANY_TYPE, null);
  } catch {
    // these files are written against several xpath engines, so a line we can't
    // compile is worth skipping rather than losing the rest of the config over
    return { nodes: [], text: null };
  }

  if (result.resultType === STRING_TYPE)
    return { nodes: [], text: result.stringValue };
  if (
    result.resultType !== UNORDERED_NODE_ITERATOR_TYPE &&
    result.resultType !== ORDERED_NODE_ITERATOR_TYPE
  ) {
    return { nodes: [], text: null };
  }

  const nodes = [];
  let node;
  while ((node = result.iterateNext())) nodes.push(node);
  return { nodes, text: null };
}

function remove(node) {
  if (node.nodeType === ATTRIBUTE_NODE) {
    if (node.ownerElement) node.ownerElement.removeAttribute(node.name);
  } else if (node.parentNode) {
    node.parentNode.removeChild(node);
  }
}

function nodeText(node) {
  if (!node) return "";
  return normalize(
    node.nodeType === ATTRIBUTE_NODE ? node.value : node.textContent,
  );
}

// strip runs over the whole document before the body is picked out, so a body
// xpath that sweeps up a share bar along with the article still comes out clean
function strip(document, config) {
  const removals = [
    ...config.strip,
    // ftr matches these against the whole attribute rather than a single class
    // name, so `sharedaddy` also takes out class="sharedaddy-wrapper"
    ...config.stripIdOrClass.map(
      (term) =>
        `//*[contains(@class, ${quote(term)}) or contains(@id, ${quote(term)})]`,
    ),
    ...config.stripImageSrc.map(
      (term) => `//img[contains(@src, ${quote(term)})]`,
    ),
    ...config.stripAttr,
  ];

  // every match is collected before anything is removed: the iterator a query
  // returns is live, and throws if the document changes while it is being read
  for (const xpath of removals) query(document, xpath).nodes.forEach(remove);
}

// several title lines mean "try these in turn", most specific first, so the
// first xpath to match anything at all decides it
function selectTitle(document, xpaths) {
  for (const xpath of xpaths) {
    const { nodes, text } = query(document, xpath);
    const title = text === null ? nodeText(nodes[0]) : normalize(text);
    if (title) return title;
  }
  return "";
}

// an author xpath matching twice is a page with two bylines rather than a
// second guess at the one byline, so those are joined instead of chosen between
function selectAuthor(document, xpaths) {
  for (const xpath of xpaths) {
    const { nodes, text } = query(document, xpath);
    const names = text === null ? nodes.map(nodeText) : [normalize(text)];
    const unique = [...new Set(names.filter(Boolean))];
    if (unique.length) return unique.join(", ");
  }
  return "";
}

function selectBody(document, config) {
  for (const xpath of config.bodies) {
    const matches = query(document, xpath).nodes.filter(
      (node) => node.nodeType === ELEMENT_NODE,
    );
    if (!matches.length) continue;

    const container = document.createElement("div");
    for (const match of matches) {
      // `//article | //article/p` is a legal body xpath & matches the same text
      // twice, so anything already inside a match is left where it is
      if (matches.some((other) => other !== match && other.contains(match)))
        continue;
      // cloned rather than moved, because readability still needs the page
      // whole if the caller ends up falling back to it
      container.appendChild(match.cloneNode(true));
    }
    return container;
  }
  return null;
}

module.exports = {
  load,
  replace,
  strip,
  selectTitle,
  selectAuthor,
  selectBody,
  normalize,
};
