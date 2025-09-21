import axios from "axios";
import { files } from "./Files";
import {
  buildWorkerMessage,
  FileType,
  type DownloadFileMessage,
} from "./WorkerTypes";
import library from "./Library";
import { compareNewslettersForDownloading } from "./compareNewsletters";

export class DownloadManager {
  private authToken: string | null = null;
  private downloadModeEnabled: boolean = false;
  private libraryInitialized: boolean = false;

  constructor() {
    files();
  }

  public async setLibraryInitialized() {
    this.libraryInitialized = true;
    await this.checkForDownloads();
    await this.checkForDeletes();
  }

  public async setAuthToken(authToken: string | null) {
    this.authToken = authToken;
    await this.checkForDownloads();
  }

  public clearAuthToken() {
    this.authToken = null;
  }

  public async setDownloadMode(enabled: boolean) {
    this.downloadModeEnabled = enabled;
    await this.checkForDownloads();
  }

  public async checkForDownloads() {
    if (
      !this.downloadModeEnabled ||
      !this.authToken ||
      !this.libraryInitialized
    ) {
      return;
    }

    const newsletters = await library().getAllNewsletters();
    const unreadNewsletters = newsletters
      .filter((n) => !n.read)
      .sort(compareNewslettersForDownloading);
    let downloadedAny = false;
    for (const newsletter of unreadNewsletters) {
      if (newsletter.epubVersion != newsletter.epubUpdatedAt) {
        downloadedAny = true;
        await this.downloadFile(newsletter.id, "epub");
      }
    }

    if (downloadedAny) {
      postMessage(buildWorkerMessage("newsletters updated", {}));
    }
  }

  async checkForDeletes() {
    if (!this.libraryInitialized) {
      return;
    }

    const newsletters = await library().getAllNewsletters();
    const readOrDeletedNewsletters = newsletters.filter(
      (n) => n.read || n.deleted,
    );
    let deletedAny = false;

    for (const newsletter of readOrDeletedNewsletters) {
      if (
        newsletter.epubLastAccessedAt &&
        (newsletter.deleted ||
          this.shouldDeleteFile(newsletter.epubLastAccessedAt))
      ) {
        if (await files().tryDeleteFile("epub", newsletter.id)) {
          deletedAny = true;
          await library().updateNewsletter(newsletter.id, () => {
            return { epubLastAccessedAt: null, epubVersion: null };
          });
        } else {
          console.error(
            "failed to delete epub file for newsletter",
            newsletter.id,
          );
        }
      }
      if (
        newsletter.sourceLastAccessedAt &&
        (newsletter.deleted ||
          this.shouldDeleteFile(newsletter.sourceLastAccessedAt))
      ) {
        if (await files().tryDeleteFile("source", newsletter.id)) {
          deletedAny = true;
          await library().updateNewsletter(newsletter.id, () => {
            return { sourceLastAccessedAt: null };
          });
        }
      }
    }

    if (deletedAny) {
      postMessage(buildWorkerMessage("newsletters updated", {}));
    }
  }

  private shouldDeleteFile(lastAccessedAt: string) {
    const ageMillis = Date.now() - new Date(lastAccessedAt).getTime();
    return ageMillis > 3 * 24 * 60 * 60 * 1000;
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

    await this.downloadFile(msg.id, msg.fileType);
    postMessage(buildWorkerMessage("newsletters updated", {}));
  }

  async downloadFile(id: number, fileType: FileType) {
    try {
      const { data } = await axios.get(`/newsletters/${id}/${fileType}`, {
        headers: { Authorization: `Bearer ${this.authToken}` },
        responseType: "arraybuffer",
        onDownloadProgress: (e) => {
          postMessage(
            buildWorkerMessage("file download status", {
              id: id,
              fileType: fileType,
              status: "in progress",
              receivedBytes: e.bytes,
              totalBytes: e.total,
            }),
          );
        },
      });
      if (await files().tryWriteFile(fileType, id, data)) {
        await this.touchFile(id, fileType);

        postMessage(
          buildWorkerMessage("file download status", {
            id: id,
            fileType: fileType,
            status: "done",
            receivedBytes: data.byteLength,
            totalBytes: data.byteLength,
          }),
        );

        postMessage(
          buildWorkerMessage("file fetched", {
            id: id,
            fileType: fileType,
          }),
        );
      } else {
        throw new Error("failed to write downloaded file");
      }
    } catch (error) {
      console.error(error);
      postMessage(
        buildWorkerMessage("file download status", {
          id: id,
          fileType: fileType,
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
