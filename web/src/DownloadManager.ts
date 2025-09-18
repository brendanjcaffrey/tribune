import axios from "axios";
import { files } from "./Files";
import { buildWorkerMessage, type DownloadFileMessage } from "./WorkerTypes";

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
