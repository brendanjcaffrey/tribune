import { TypedWorker } from "./TypedWorker";

export const DownloadWorkerUntyped = new Worker(
  new URL("./DownloadManager.ts", import.meta.url),
  {
    type: "module",
  },
);

export const DownloadWorker = new TypedWorker(DownloadWorkerUntyped);
