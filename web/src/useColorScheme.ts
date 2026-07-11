import { useSyncExternalStore } from "react";

// tracks the os color scheme so components that read bootstrap css vars in js
// (background, ag-grid, epub iframe) re-render when the user flips light/dark.
// the data-bs-theme attribute itself is set by the inline script in index.html.

const query = "(prefers-color-scheme: dark)";

function subscribe(callback: () => void) {
  const mq = window.matchMedia(query);
  mq.addEventListener("change", callback);
  return () => mq.removeEventListener("change", callback);
}

function getSnapshot(): "dark" | "light" {
  return window.matchMedia(query).matches ? "dark" : "light";
}

export function useColorScheme(): "dark" | "light" {
  return useSyncExternalStore(subscribe, getSnapshot);
}
