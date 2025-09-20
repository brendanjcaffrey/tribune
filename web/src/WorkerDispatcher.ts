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

  switch (msg.type) {
    case "set auth token":
      syncManager.setAuthToken(msg.authToken);
      downloadManager.setAuthToken(msg.authToken);
      updateManager.setAuthToken(msg.authToken);
      break;
    case "clear auth token":
      syncManager.clearAuthToken();
      downloadManager.clearAuthToken();
      updateManager.clearAuthToken();
      break;
    case "start sync":
      syncManager.forceSyncLibrary();
      break;
    case "download file":
      downloadManager.startDownload(msg);
      break;
    case "mark newsletter as read":
      updateManager.markNewsletterAsRead(msg.id);
      break;
    case "mark newsletter as unread":
      updateManager.markNewsletterAsUnread(msg.id);
      break;
    case "mark newsletter as deleted":
      updateManager.markNewsletterAsDeleted(msg.id);
      break;
    case "update newsletter progress":
      updateManager.updateNewsletterProgress(msg.id, msg.progress);
      break;
    default:
      console.error("Unknown message type:", msg);
      break;
  }
};
