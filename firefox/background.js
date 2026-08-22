const ext = typeof browser !== "undefined" ? browser : chrome;

const BADGE_COLORS = {
  working: "#666666",
  ok: "#2e7d32",
  error: "#c62828",
};

// the server falls back to downloading anything we don't send, so these caps
// only trade upload size against how much work the server has to redo
const MAX_IMAGES = 100;
const MAX_IMAGE_BYTES = 10 * 1024 * 1024;

async function getSettings() {
  return await ext.storage.local.get();
}

function setBadge(tabId, text, state) {
  // set the color first so there isn't a flash from the previous badge when it was cleared
  ext.action.setBadgeBackgroundColor({ tabId, color: BADGE_COLORS[state] });
  ext.action.setBadgeText({ tabId, text });
}

function clearBadgeLater(tabId) {
  setTimeout(() => ext.action.setBadgeText({ tabId, text: "" }), 5000);
}

function notify(title, message) {
  ext.notifications.create({
    type: "basic",
    iconUrl: ext.runtime.getURL("icons/icon96.png"),
    title,
    message,
  });
}

const SETTINGS_MENU_ID = "open-settings";

// add a "settings" entry to the context menu on the toolbar button.
// removeAll() first so we don't get a duplicate-id error when the event page wakes up again.
ext.menus.removeAll().then(() => {
  ext.menus.create({
    id: SETTINGS_MENU_ID,
    title: "Settings",
    contexts: ["action"],
  });
});

ext.menus.onClicked.addListener((info) => {
  if (info.menuItemId === SETTINGS_MENU_ID) {
    ext.runtime.openOptionsPage();
  }
});

async function checkAuth(apiUrl, apiKey) {
  const resp = await fetch(`${apiUrl}/auth`, {
    headers: { Authorization: `Bearer ${apiKey}` },
  });

  if (!resp.ok) {
    const text = await resp.text().catch(() => "");
    throw new Error(
      `Auth check failed (${resp.status}): ${text || resp.statusText}`,
    );
  }

  const body = await resp.json().catch(() => ({}));
  if (!body.username) {
    throw new Error("Auth check failed: no username in response");
  }

  console.log(`Authenticated as ${body.username}`);
}

// fetched from the background rather than the page so cross-origin images
// aren't blocked by the page's CORS rules. cookies are included & the http cache
// is preferred so we get the same bytes the page just rendered, which is the
// whole point of sending these instead of letting the server download them.
async function fetchImages(images) {
  const settled = await Promise.allSettled(
    images.slice(0, MAX_IMAGES).map(async ({ src, fetchSrc }) => {
      const resp = await fetch(fetchSrc, {
        credentials: "include",
        cache: "force-cache",
      });
      if (!resp.ok) throw new Error(`${resp.status} ${resp.statusText}`);

      const blob = await resp.blob();
      if (!blob.size || blob.size > MAX_IMAGE_BYTES) {
        throw new Error(`unusable size ${blob.size}`);
      }
      return { src, blob };
    }),
  );

  const fetched = [];
  settled.forEach((outcome, i) => {
    if (outcome.status === "fulfilled") {
      fetched.push(outcome.value);
    } else {
      console.warn(`skipping image ${images[i].fetchSrc}:`, outcome.reason);
    }
  });
  return fetched;
}

// when the toolbar button is clicked, inject the content script, collect HTML+metadata, then upload.
ext.action.onClicked.addListener(async (tab) => {
  try {
    if (!tab.id) throw new Error("No active tab");

    const { apiUrl, apiKey } = await getSettings();
    if (!apiUrl || !apiKey) {
      throw new Error("Set the API URL and key in the extension options first");
    }

    setBadge(tab.id, "…", "working");
    ext.action.setTitle({ tabId: tab.id, title: "Pushing to Tribune…" });
    await checkAuth(apiUrl, apiKey);

    // Inject the content script into the active tab
    const [{ result }] = await ext.scripting.executeScript({
      target: { tabId: tab.id, allFrames: false },
      func: () => {
        // this runs in the page context
        const d = document;
        const dt = d.doctype
          ? `<!DOCTYPE ${d.doctype.name}${
              d.doctype.publicId ? ` PUBLIC "${d.doctype.publicId}"` : ""
            }${d.doctype.systemId ? ` "${d.doctype.systemId}"` : ""}>`
          : "";
        const html = dt + "\n" + d.documentElement.outerHTML;

        // src is what ends up in the html we upload, so the server keys off it.
        // currentSrc is what the browser actually loaded (i.e. the srcset pick),
        // so it's the one worth fetching & the one most likely to still be cached.
        const seen = new Set();
        const images = [];
        for (const img of d.images) {
          const attr = img.getAttribute("src");
          if (!attr) continue;

          let src;
          try {
            src = new URL(attr, d.location.href).href;
          } catch {
            continue;
          }
          if (!/^https?:/.test(src) || seen.has(src)) continue;

          seen.add(src);
          const fetchSrc = /^https?:/.test(img.currentSrc || "")
            ? img.currentSrc
            : src;
          images.push({ src, fetchSrc });
        }

        return {
          url: d.location.href,
          html,
          images,
        };
      },
    });

    const filename = "source.html";
    const form = new FormData();
    const htmlBlob = new Blob([result.html], { type: "text/html" });
    form.append("raw_source_file", htmlBlob, filename);

    // the field names are how the server pairs each upload back up with the
    // src it should replace in the html
    const images = await fetchImages(result.images || []);
    const imageMetadata = images.map(({ src, blob }, i) => {
      const field = `image_${i}`;
      form.append(field, blob, field);
      return { field, src };
    });

    const metadata = { url: result.url, images: imageMetadata };
    const jsonBlob = new Blob([JSON.stringify(metadata)], {
      type: "application/json",
    });
    form.append("metadata", jsonBlob);

    const resp = await fetch(`${apiUrl}/newsletters/raw`, {
      method: "POST",
      body: form,
      headers: { Authorization: `Bearer ${apiKey}` },
    });

    if (!resp.ok) {
      const text = await resp.text().catch(() => "");
      throw new Error(
        `Upload failed (${resp.status}): ${text || resp.statusText}`,
      );
    }

    const body = await resp.json().catch(() => ({}));

    setBadge(tab.id, "✓", "ok");
    ext.action.setTitle({
      tabId: tab.id,
      title: `Page pushed to Tribune (id ${body.id || "unknown"})`,
    });
    clearBadgeLater(tab.id);
  } catch (err) {
    console.error("Push to Tribune error:", err);
    if (tab.id) {
      setBadge(tab.id, "✕", "error");
      ext.action.setTitle({ tabId: tab.id, title: `Failed: ${err.message}` });
      clearBadgeLater(tab.id);
    }
    notify("Push to Tribune failed", err.message);
  }
});
