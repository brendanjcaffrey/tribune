import axios from "axios";
import { files } from "./Files";
import {
  buildWorkerMessage,
  FileType,
  type DownloadFileMessage,
} from "./WorkerTypes";
import library from "./Library";

export class DownloadManager {
  private authToken: string | null = null;
  private downloadModeEnabled: boolean = false;

  constructor() {
    files();
  }

  public async setAuthToken(authToken: string | null) {
    this.authToken = authToken;
  }

  public clearAuthToken() {
    this.authToken = null;
  }

  public setDownloadModeEnabled(enabled: boolean) {
    this.downloadModeEnabled = enabled;
  }

  public async startDownload(msg: DownloadFileMessage) {
    if (!this.authToken) {
      return;
    }

    let exists = await files().fileExists(msg.fileType, msg.id);
    if (msg.fileType === "epub") {
      const newsletter = await library().getNewsletter(msg.id);
      if (newsletter && newsletter.epubVersion != newsletter.epubUpdatedAt) {
        // epub version has changed, need to re-download
        exists = false;
      }
    }

    if (exists) {
      // file already exists, no need to download again
      postMessage(
        buildWorkerMessage("file fetched", {
          id: msg.id,
          fileType: msg.fileType,
        }),
      );
      await this.touchFile(msg.id, msg.fileType);
      return;
    }

    try {
      const { data } = await axios.get(
        `/newsletters/${msg.id}/${msg.fileType}`,
        {
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
        },
      );
      if (await files().tryWriteFile(msg.fileType, msg.id, data)) {
        await this.touchFile(msg.id, msg.fileType);

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
      } else {
        throw new Error("failed to write downloaded file");
      }
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

  async touchFile(id: number, fileType: FileType) {
    if (fileType === "epub") {
      library().updateNewsletter(id, (n) => {
        return {
          epubVersion: n.epubUpdatedAt,
          epubLastAccessedAt: new Date().toISOString(),
        };
      });
    } else {
      library().updateNewsletter(id, () => {
        return {
          sourceLastAccessedAt: new Date().toISOString(),
        };
      });
    }
  }
}
