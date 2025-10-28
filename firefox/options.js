const ext = typeof browser !== "undefined" ? browser : chrome;

async function load() {
  const { apiUrl, apiKey } = await ext.storage.local.get();
  document.getElementById("apiUrl").value = apiUrl || "";
  document.getElementById("apiKey").value = apiKey || "";
}

async function save() {
  const apiUrl = document.getElementById("apiUrl").value.trim();
  const apiKey = document.getElementById("apiKey").value;
  await ext.storage.local.set({ apiUrl, apiKey });

  const s = document.getElementById("status");
  s.textContent = "Saved";
  setTimeout(() => (s.textContent = ""), 750);
}

document.getElementById("saveBtn").addEventListener("click", save);
document.addEventListener("DOMContentLoaded", load);
