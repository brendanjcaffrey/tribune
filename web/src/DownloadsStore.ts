import { memoize } from "lodash";
import { Mutex } from "async-mutex";
import { LRUCache } from "typescript-lru-cache";
import library from "./Library";
import {
  FileDownloadStatusMessage,
  FileType,
  DownloadStatus,
} from "./WorkerTypes";
import { store, anyDownloadErrorsAtom } from "./State";

const DEFAULT_MAX_SIZE = 100;

export interface Download {
  id: number;
  fileType: FileType;
  status: DownloadStatus;
  receivedBytes: number | undefined;
  totalBytes: number | undefined;
  trackDesc: string;
  lastUpdate: number;
}

export class DownloadsStore {
  private mutex = new Mutex();
  private cache = new LRUCache<string, string>();
  private downloads: Download[] = [];
  private maxSize: number;

  constructor(maxSize: number = DEFAULT_MAX_SIZE) {
    this.maxSize = maxSize;
  }

  async update(newStatus: FileDownloadStatusMessage) {
    await this.mutex.runExclusive(async () => this.updateExclusive(newStatus));
  }

  async updateExclusive(newStatus: FileDownloadStatusMessage) {
    const descKey = `${newStatus.id}-${newStatus.fileType}`;
    let newsletterDesc = this.cache.get(descKey);
    if (!newsletterDesc) {
      const newsletter = await library().getNewsletter(newStatus.id);
      if (!newsletter) {
        return;
      }

      newsletterDesc = `${newsletter.title} - ${newsletter.author}`;
      this.cache.set(descKey, newsletterDesc);
    }

    // remove any existing entry with the same id/file type
    this.downloads = this.downloads.filter(
      (d) => d.id !== newStatus.id || d.fileType !== newStatus.fileType,
    );

    const download: Download = {
      id: newStatus.id,
      fileType: newStatus.fileType,
      status: newStatus.status,
      receivedBytes: newStatus.receivedBytes,
      totalBytes: newStatus.totalBytes,
      trackDesc: newsletterDesc,
      lastUpdate: Date.now(),
    };
    this.downloads.unshift(download);

    if (this.downloads.length > this.maxSize) {
      this.downloads.pop();
    }

    store.set(
      anyDownloadErrorsAtom,
      this.downloads.some((d) => d.status === "error"),
    );
  }

  getAll(): Download[] {
    return [...this.downloads]; // return a copy to prevent external mutations
  }

  clear() {
    this.downloads = [];
  }
}

const downloadsStore = memoize(() => new DownloadsStore());
downloadsStore();
export default downloadsStore;
