import { TypedWorker } from "./TypedWorker";

export const SyncWorkerUntyped = new Worker(
  new URL("./SyncManager.ts", import.meta.url),
  {
    type: "module",
  },
);

export const SyncWorker = new TypedWorker(SyncWorkerUntyped);
