const ext = typeof browser !== "undefined" ? browser : chrome;

const BADGE_COLORS = {
  working: "#666666",
  ok: "#2e7d32",
  error: "#c62828",
};

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

// when the toolbar button is clicked, inject the content script, collect HTML+metadata, then upload.
ext.action.onClicked.addListener(async (tab) => {
  try {
    if (!tab.id) throw new Error("No active tab");

    setBadge(tab.id, "…", "working");
    ext.action.setTitle({ tabId: tab.id, title: "Pushing to Tribune…" });

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

        return {
          url: d.location.href,
          html,
        };
      },
    });

    // post to API as multipart/form-data from the background (to bypass page CORS)
    const { apiUrl, apiKey } = await getSettings();
    if (!apiUrl || !apiKey) {
      throw new Error("Set the API URL and key in the extension options first");
    }

    const filename = "source.html";
    const form = new FormData();
    const htmlBlob = new Blob([result.html], { type: "text/html" });
    form.append("raw_source_file", htmlBlob, filename);

    const metadata = { url: result.url };
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
