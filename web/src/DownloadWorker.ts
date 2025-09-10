import { TypedWorker } from "./TypedWorker";

export const DownloadWorker = new TypedWorker(
  new URL("./DownloadManager.ts", import.meta.url),
  {
    type: "module",
  },
);
