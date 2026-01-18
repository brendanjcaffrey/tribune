import JSZip from "jszip";

export interface SpineItem {
  headContent: string;
  bodyContent: string;
}

interface ManifestItem {
  id: string;
  href: string;
  mediaType: string;
}

const TEXT_EXTENSIONS = [
  ".xhtml",
  ".html",
  ".xml",
  ".opf",
  ".ncx",
  ".css",
  ".js",
];

export class Epub {
  private files = new Map<string, string | Blob>();
  rootfilePath: string | undefined;
  manifest = new Map<string, ManifestItem>();
  spine: string[] = [];

  constructor(private data: ArrayBuffer | Uint8Array) {}

  public async parse() {
    await this.unzip();
    this.rootfilePath = this.getRootfilePath();
    await this.parseRootfile();
  }

  private async unzip() {
    const zip = await JSZip.loadAsync(this.data);
    for (const [relativePath, zipEntry] of Object.entries(zip.files)) {
      if (!zipEntry.dir) {
        let content: string | Blob;
        const extension = relativePath.split(".").pop()?.toLowerCase() || "";
        if (TEXT_EXTENSIONS.includes(`.${extension}`)) {
          content = await zipEntry.async("text");
        } else {
          content = await zipEntry.async("blob");
        }
        this.files.set(relativePath, content);
      }
    }
  }

  private getRootfilePath(): string {
    const containerXmlPath = "META-INF/container.xml";
    const containerXml = this.files.get(containerXmlPath);

    if (!containerXml || typeof containerXml !== "string") {
      throw new Error(`'${containerXmlPath}' not found in EPUB`);
    }

    const parser = new DOMParser();
    const doc = parser.parseFromString(containerXml, "application/xml");
    const rootfile = doc.querySelector("rootfile");

    if (!rootfile) {
      throw new Error("No <rootfile> element found in container.xml");
    }

    const fullPath = rootfile.getAttribute("full-path");
    if (!fullPath) {
      throw new Error('No "full-path" attribute found on <rootfile> element');
    }

    if (!this.files.has(fullPath)) {
      throw new Error(`Root file "${fullPath}" not found in EPUB`);
    }

    return fullPath;
  }

  private async parseRootfile() {
    if (!this.rootfilePath) {
      throw new Error("Root file path not found.");
    }

    const rootfileContent = this.files.get(this.rootfilePath);
    if (!rootfileContent || typeof rootfileContent !== "string") {
      throw new Error("Root file content not found or not a string.");
    }

    const parser = new DOMParser();
    const doc = parser.parseFromString(rootfileContent, "application/xml");

    // parse manifest
    const manifestItems = doc.querySelectorAll("manifest item");
    manifestItems.forEach((item) => {
      const id = item.getAttribute("id");
      const href = item.getAttribute("href");
      const mediaType = item.getAttribute("media-type");
      if (id && href && mediaType) {
        const hrefPath = this.resolvePath(href, this.rootfilePath!);
        this.manifest.set(id, { id, href: hrefPath, mediaType });
      }
    });

    // parse spine
    const spineItems = doc.querySelectorAll("spine itemref");
    spineItems.forEach((item) => {
      const idref = item.getAttribute("idref");
      if (idref) {
        this.spine.push(idref);
      }
    });
  }

  public async getSpineItem(spineIndex: number): Promise<SpineItem> {
    if (spineIndex < 0 || spineIndex >= this.spine.length) {
      throw new Error("Spine index out of bounds");
    }

    const idref = this.spine[spineIndex];
    const manifestItem = this.manifest.get(idref);

    if (!manifestItem) {
      throw new Error(`Item with idref "${idref}" not found in manifest`);
    }

    const itemPath = manifestItem.href;
    const itemContent = this.files.get(itemPath);

    if (!itemContent || typeof itemContent !== "string") {
      throw new Error(`Content for "${itemPath}" not found or not a string`);
    }

    // DOMParser chokes on these epub:type attributes, so we replace them
    const contentWithFixedFootnotes = itemContent.replaceAll(
      "epub:type",
      "epub_type",
    );

    const parser = new DOMParser();
    const doc = parser.parseFromString(
      contentWithFixedFootnotes,
      "application/xhtml+xml",
    );

    // update links - any footnote links should navigate and other links should open in a new tab
    const anchors = doc.querySelectorAll("a");
    for (const anchor of Array.from(anchors)) {
      const href = anchor.getAttribute("href");
      if (anchor.hasAttribute("epub_type")) {
        if (href) {
          anchor.setAttribute(
            "onclick",
            `window.parent.dispatchEvent(new CustomEvent('scrollToHref', { detail: { href: '${href}' } })); return false;`,
          );
        }
      } else {
        if (href && (href.startsWith("http") || href.startsWith("https"))) {
          anchor.setAttribute("target", "_blank");
          anchor.setAttribute("rel", "noopener noreferrer");
        }
      }
    }

    // inline images
    const images = doc.querySelectorAll("img");
    for (const img of Array.from(images)) {
      const src = img.getAttribute("src");
      if (src) {
        const imagePath = this.resolvePath(src, itemPath);
        const imageBlob = this.files.get(imagePath);
        if (imageBlob instanceof Blob) {
          const dataUrl = await this.blobToDataURL(imageBlob);
          img.setAttribute("src", dataUrl);
        }
      }
    }

    // inline stylesheets
    const links = doc.querySelectorAll('link[rel="stylesheet"]');
    for (const link of Array.from(links)) {
      const href = link.getAttribute("href");
      if (href) {
        const cssPath = this.resolvePath(href, itemPath);
        const cssContent = this.files.get(cssPath);
        if (typeof cssContent === "string") {
          const style = doc.createElement("style");
          style.textContent = cssContent;
          link.replaceWith(style);
        }
      }
    }

    return { headContent: doc.head.innerHTML, bodyContent: doc.body.innerHTML };
  }

  private resolvePath(href: string, basePath: string): string {
    const base = basePath.substring(0, basePath.lastIndexOf("/"));
    const pathParts = (base + "/" + href).split("/");
    const resolvedParts: string[] = [];
    for (const part of pathParts) {
      if (part === "." || part === "") continue;
      if (part === "..") {
        resolvedParts.pop();
      } else {
        resolvedParts.push(part);
      }
    }
    return resolvedParts.join("/");
  }

  private blobToDataURL(blob: Blob): Promise<string> {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onloadend = () => resolve(reader.result as string);
      reader.onerror = reject;
      reader.readAsDataURL(blob);
    });
  }
}
