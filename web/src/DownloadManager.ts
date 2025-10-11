import axios from "axios";
import { files } from "./Files";
import {
  buildWorkerMessage,
  FileType,
  type DownloadFileMessage,
} from "./WorkerTypes";
import library from "./Library";
import { compareNewslettersForDownloading } from "./compareNewsletters";
import { Mutex } from "async-mutex";

export class DownloadManager {
  private authToken: string | null = null;
  private downloadModeEnabled: boolean = false;
  private downloadPDFsEnabled: boolean = false;
  private libraryInitialized: boolean = false;
  private abortController: AbortController | null = null;
  private mutex: Mutex;

  constructor(mutex: Mutex) {
    this.mutex = mutex;
    files();

    setInterval(
      () => {
        this.checkForDeletes();
      },
      12 * 60 * 60 * 1000,
    );
  }

  public async setLibraryInitialized() {
    this.libraryInitialized = true;
    await this.checkForDownloads();
    await this.checkForDeletes();
  }

  public async setAuthToken(authToken: string | null) {
    this.authToken = authToken;
    await this.checkForDownloads();
    await this.checkForDeletes();
  }

  public clearAuthToken() {
    this.authToken = null;
    if (this.abortController) {
      this.abortController.abort();
    }
  }

  public async setDownloadMode(enabled: boolean) {
    this.downloadModeEnabled = enabled;
    await this.checkForDownloads();
  }

  public async setDownloadPDFs(enabled: boolean) {
    this.downloadPDFsEnabled = enabled;
    await this.checkForDownloads();
  }

  public checkForDownloads(): Promise<void> {
    return this.mutex.runExclusive(async () =>
      this.checkForDownloadsExclusive(),
    );
  }

  private async checkForDownloadsExclusive() {
    if (
      !this.downloadModeEnabled ||
      !this.authToken ||
      !this.libraryInitialized
    ) {
      return;
    }

    const newsletters = await library().getAllNewsletters();
    const unreadNewsletters = newsletters
      .filter((n) => !n.read && !n.deleted)
      .sort(compareNewslettersForDownloading);
    let downloadedAny = false;
    for (const newsletter of unreadNewsletters) {
      if (newsletter.epubVersion != newsletter.epubUpdatedAt) {
        downloadedAny = true;
        await this.downloadFile(newsletter.id, "epub");
      }
      if (!this.authToken) {
        // logged out in the middle
        return;
      }
    }

    if (this.downloadPDFsEnabled) {
      for (const newsletter of unreadNewsletters) {
        if (
          newsletter.sourceMimeType == "application/pdf" &&
          newsletter.sourceLastAccessedAt == null
        ) {
          downloadedAny = true;
          await this.downloadFile(newsletter.id, "source");
        }
        if (!this.authToken) {
          // logged out in the middle
          return;
        }
      }
    }

    if (downloadedAny) {
      postMessage(buildWorkerMessage("newsletters updated", {}));
    }
  }

  public checkForDeletes(): Promise<void> {
    return this.mutex.runExclusive(async () => this.checkForDeletesExclusive());
  }

  private async checkForDeletesExclusive() {
    if (!this.libraryInitialized || !this.authToken) {
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
          // logged out in the middle
          if (!this.authToken) {
            return;
          }
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
        } else {
          // logged out in the middle
          if (!this.authToken) {
            return;
          }
          console.error(
            "failed to delete source file for newsletter",
            newsletter.id,
          );
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
      postMessage(
        buildWorkerMessage("file download status", {
          id: id,
          fileType: fileType,
          status: "in progress",
          receivedBytes: 0,
          totalBytes: 0,
        }),
      );

      this.abortController = new AbortController();
      const { data } = await axios.get(`/newsletters/${id}/${fileType}`, {
        signal: this.abortController.signal,
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
      if (!this.abortController?.signal.aborted) {
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
    } finally {
      this.abortController = null;
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
