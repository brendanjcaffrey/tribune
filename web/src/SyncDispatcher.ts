import { DownloadManager } from "./DownloadManager";
import { SyncManager } from "./SyncManager";
import { MainToWorkerMessage } from "./WorkerTypes";

const syncManager = new SyncManager();
const downloadManager = new DownloadManager();

onmessage = (ev: MessageEvent<MainToWorkerMessage>) => {
  const msg = ev.data;

  if (msg.type === "set auth token") {
    syncManager.setAuthToken(msg.authToken);
    downloadManager.setAuthToken(msg.authToken);
  } else if (msg.type === "clear auth token") {
    syncManager.clearAuthToken();
    downloadManager.clearAuthToken();
  } else if (msg.type === "download file") {
    downloadManager.startDownload(msg);
  }
};
