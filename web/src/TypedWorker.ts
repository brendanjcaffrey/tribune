import type { MainToWorkerMessage, WorkerToMainMessage } from "./WorkerTypes";

export type TypedWorkerMessageListener = (ev: MessageEvent) => void;
export class TypedWorker {
  constructor(private worker: Worker) {
    this.worker = worker;
  }

  postMessage(message: MainToWorkerMessage): void {
    this.worker.postMessage(message);
  }

  addMessageListener(
    listener: (
      msg: WorkerToMainMessage,
      ev: MessageEvent<WorkerToMainMessage>,
    ) => void,
  ): TypedWorkerMessageListener {
    const wrapper = (ev: MessageEvent) => {
      const data = ev.data;
      listener(
        data as WorkerToMainMessage,
        ev as MessageEvent<WorkerToMainMessage>,
      );
    };
    this.worker.addEventListener("message", wrapper);
    return wrapper;
  }

  removeMessageListener(listener: TypedWorkerMessageListener): void {
    this.worker.removeEventListener("message", listener);
  }
}
