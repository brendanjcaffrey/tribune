import axios from "axios";
import { files } from "./Files";
import {
  buildWorkerMessage,
  type DownloadFileMessage,
  type MainToWorkerMessage,
} from "./WorkerTypes";

export class DownloadManager {
  private authToken: string | null = null;

  constructor() {
    files();
  }

  public async setAuthToken(authToken: string | null) {
    this.authToken = authToken;
  }

  public clearAuthToken() {
    this.authToken = null;
  }

  public async startDownload(msg: DownloadFileMessage) {
    if (!this.authToken) {
      return;
    }

    try {
      const { data } = await axios.get(`/newsletters/${msg.id}/epub`, {
        headers: { Authorization: `Bearer ${this.authToken}` },
        responseType: "arraybuffer",
        onDownloadProgress: (e) => {
          postMessage(
            buildWorkerMessage("file download status", {
              id: msg.id,
              fileType: msg.fileType,
              status: "in progress",
              receivedBytes: e.bytes,
              totalBytes: e.total,
            }),
          );
        },
      });
      if (await files().tryWriteFile(msg.fileType, msg.id, data)) {
        postMessage(
          buildWorkerMessage("file download status", {
            id: msg.id,
            fileType: msg.fileType,
            status: "done",
            receivedBytes: data.byteLength,
            totalBytes: data.byteLength,
          }),
        );
        postMessage(
          buildWorkerMessage("file fetched", {
            id: msg.id,
            fileType: msg.fileType,
          }),
        );
      }
      // TODO handle this failure somehow?
    } catch (error) {
      console.error(error);
      postMessage(
        buildWorkerMessage("file download status", {
          id: msg.id,
          fileType: msg.fileType,
          status: "error",
          receivedBytes: undefined,
          totalBytes: undefined,
        }),
      );
    }
  }
}

const downloadManager = new DownloadManager();

onmessage = (ev: MessageEvent<MainToWorkerMessage>) => {
  const msg = ev.data;

  if (msg.type === "set auth token") {
    downloadManager.setAuthToken(msg.authToken);
  } else if (msg.type === "clear auth token") {
    downloadManager.clearAuthToken();
  } else if (msg.type == "download file") {
    downloadManager.startDownload(msg);
  }
};
