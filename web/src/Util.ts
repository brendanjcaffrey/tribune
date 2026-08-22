import { enqueueToast } from "./Toasts";

export function formatBytes(bytes: number, decimals = 2) {
  if (!bytes) {
    return "0b";
  }
  const k = 1024;
  const sizes = ["b", "kb", "mb", "gb", "tb"];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return `${parseFloat((bytes / Math.pow(k, i)).toFixed(decimals))} ${
    sizes[i]
  }`;
}

export function formatTimestamp(time: number): string {
  const date = new Date(time);
  const now = new Date();

  const isSameDay =
    date.getFullYear() === now.getFullYear() &&
    date.getMonth() === now.getMonth() &&
    date.getDate() === now.getDate();

  const timeFormatter = new Intl.DateTimeFormat(undefined, {
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    fractionalSecondDigits: 3,
    hour12: true,
  });

  const timeString = timeFormatter.format(date);

  if (isSameDay) {
    return timeString;
  }

  const dateFormatter = new Intl.DateTimeFormat(undefined, {
    month: "2-digit",
    day: "2-digit",
  });

  return `${dateFormatter.format(date)} ${timeString}`;
}

// opens a source url in a new tab. passing noopener in the features string makes
// window.open always return null, so sever the opener afterwards instead and keep the
// null check meaningful
export function openSourceUrl(url: string) {
  const handle = window.open(url, "_blank");
  if (handle === null) {
    enqueueToast("Failed to open url, check popup blocker settings", {
      variant: "error",
    });
  } else {
    handle.opener = null;
  }
}

// the source id is a url when the newsletter came from a saved web page, so it can be
// opened in the browser. emails and the like use other schemes, which aren't openable
export function sourceUrl(sourceId: string | null | undefined): string | null {
  if (!sourceId) {
    return null;
  }
  let url;
  try {
    url = new URL(sourceId);
  } catch {
    return null;
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return null;
  }
  if (url.hostname === "") {
    return null;
  }
  return url.href;
}
