import { DownloadManager } from "./DownloadManager";
import library from "./Library";
import { SyncManager } from "./SyncManager";
import { UpdateManager } from "./UpdateManager";
import { MainToWorkerMessage } from "./WorkerTypes";

const syncManager = new SyncManager();
const downloadManager = new DownloadManager();
const updateManager = new UpdateManager();

library().setInitializedListener(async () => {
  syncManager.setLibraryInitialized();
  updateManager.setLibraryInitialized();
});

onmessage = (ev: MessageEvent<MainToWorkerMessage>) => {
  const msg = ev.data;

  if (msg.type === "set auth token") {
    syncManager.setAuthToken(msg.authToken);
    downloadManager.setAuthToken(msg.authToken);
    updateManager.setAuthToken(msg.authToken);
  } else if (msg.type === "clear auth token") {
    syncManager.clearAuthToken();
    downloadManager.clearAuthToken();
    updateManager.clearAuthToken();
  } else if (msg.type === "download file") {
    downloadManager.startDownload(msg);
  } else if (msg.type === "mark newsletter as read") {
    updateManager.markNewsletterAsRead(msg.id);
  } else if (msg.type === "mark newsletter as unread") {
    updateManager.markNewsletterAsUnread(msg.id);
  } else if (msg.type === "mark newsletter as deleted") {
    updateManager.markNewsletterAsDeleted(msg.id);
  }
};
