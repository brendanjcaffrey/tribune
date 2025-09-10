import type { MainToWorkerMessage, WorkerToMainMessage } from "./WorkerTypes";

export type TypedWorkerMessageListener = (ev: MessageEvent) => void;
export class TypedWorker extends Worker {
  postMessage(message: MainToWorkerMessage): void {
    super.postMessage(message);
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
    this.addEventListener("message", wrapper);
    return wrapper;
  }

  removeMessageListener(listener: TypedWorkerMessageListener): void {
    this.removeEventListener("message", listener);
  }
}
