import { TypedWorker } from "./TypedWorker";

export const WorkerInstanceRaw = new Worker(
  new URL("./WorkerDispatcher.ts", import.meta.url),
  {
    type: "module",
  },
);

export const WorkerInstance = new TypedWorker(WorkerInstanceRaw);
