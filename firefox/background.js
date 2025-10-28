const ext = typeof browser !== "undefined" ? browser : chrome;

async function getSettings() {
  return await ext.storage.local.get();
}

// when the toolbar button is clicked, inject the content script, collect HTML+metadata, then upload.
ext.action.onClicked.addListener(async (tab) => {
  try {
    if (!tab.id) throw new Error("No active tab");

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

    console.log("Upload complete");
  } catch (err) {
    console.error("Push to Tribune error:", err);
  }
});
