import { TypedWorker } from "./TypedWorker";

export const SyncWorker = new TypedWorker(
  new URL("./SyncManager.ts", import.meta.url),
  {
    type: "module",
  },
);
