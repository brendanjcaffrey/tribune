import type { MainToWorkerMessage } from "./WorkerTypes";

export class DownloadManager {
  private authToken: string | null = null;

  public async setAuthToken(authToken: string | null) {
    this.authToken = authToken;
  }
}

const downloadManager = new DownloadManager();

onmessage = (ev: MessageEvent<MainToWorkerMessage>) => {
  const msg = ev.data;

  if (msg.type === "auth token") {
    downloadManager.setAuthToken(msg.authToken);
  }
};
