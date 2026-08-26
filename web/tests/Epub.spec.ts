import { expect, test } from "vitest";
import { Epub } from "../src/Epub";

// the reader frames the book before the epub has parsed, so a null spine item
// used to end up interpolated as the literal string "undefined" and flash on
// screen until the real content arrived
test("renders nothing for a null spine item", () => {
  const content = Epub.buildIframeContent(
    300,
    "body { color: red; }",
    null,
    80,
  );
  expect(content).not.toContain("undefined");
});

test("renders the spine item content", () => {
  const content = Epub.buildIframeContent(
    300,
    "body { color: red; }",
    { headContent: "<title>an article</title>", bodyContent: "<p>hello</p>" },
    80,
  );
  expect(content).toContain("<p>hello</p>");
  expect(content).not.toContain("undefined");
});
