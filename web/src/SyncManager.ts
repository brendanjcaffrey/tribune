import axios from "axios";
import { Mutex } from "async-mutex";
import { buildWorkerMessage } from "./WorkerTypes";
import library, { type Newsletter } from "./Library";
import { compareNewslettersForApi } from "./compareNewsletters";
import { type APINewsletters } from "./APINewsletters";
import { DownloadManager } from "./DownloadManager";

const REFRESH_MILLIS = 5 * 60 * 1000;

export class SyncManager {
  private downloadManager: DownloadManager;
  private mutex: Mutex;
  private authToken: string | null = null;
  private libraryInitialized: boolean = false;
  private timerId: NodeJS.Timeout | null = null;
  private abortController: AbortController | null = null;

  constructor(downloadManager: DownloadManager, mutex: Mutex) {
    this.downloadManager = downloadManager;
    this.mutex = mutex;
  }

  public async setLibraryInitialized() {
    this.libraryInitialized = true;
    await this.syncLibrary();
  }

  public async setAuthToken(authToken: string) {
    this.authToken = authToken;
    await this.syncLibrary();
  }

  public clearAuthToken() {
    this.authToken = null;
    if (this.abortController) {
      this.abortController.abort();
    }
  }

  forceSyncLibrary() {
    /* unawaited */ this.syncLibrary(true);
    postMessage(buildWorkerMessage("info", { info: "Sync started" }));
  }

  syncLibrary(notifyDone: boolean = false): Promise<void> {
    return this.mutex.runExclusive(async () =>
      this.syncLibraryExclusive(notifyDone),
    );
  }

  private async syncLibraryExclusive(notifyDone: boolean = false) {
    if (this.authToken === null || !this.libraryInitialized) {
      return;
    }

    if (this.timerId !== null) {
      clearInterval(this.timerId);
      this.timerId = null;
    }

    try {
      postMessage(buildWorkerMessage("sync status", { running: true }));
      this.abortController = new AbortController();
      if (await library().hasAnyNewsletters()) {
        await this.fetchUpdates();
      } else {
        await this.fetchInitial();
      }
      this.downloadManager.checkForDownloads();
    } catch (error) {
      if (!this.abortController?.signal.aborted) {
        console.error(error);
        if (error instanceof Error) {
          postMessage(buildWorkerMessage("error", { error: error.message }));
        } else {
          postMessage(buildWorkerMessage("error", { error: "unknown error" }));
        }
      }
    } finally {
      this.abortController = null;
      if (this.authToken !== null) {
        this.timerId = setTimeout(() => this.syncLibrary(), REFRESH_MILLIS);
      }
      postMessage(buildWorkerMessage("sync status", { running: false }));
      if (notifyDone) {
        postMessage(
          buildWorkerMessage("success", { success: "Sync succeeded" }),
        );
      }
    }
  }

  private async fetchInitial() {
    const { data } = await axios.get<APINewsletters>("/newsletters", {
      signal: this.abortController!.signal,
      headers: { Authorization: `Bearer ${this.authToken}` },
      params: {}, // this is here for unit tests
    });
    for (const newsletter of this.transformResponse(data)) {
      await library().putNewsletter(newsletter);
    }
    if (data.result.length > 0) {
      postMessage(buildWorkerMessage("newsletters updated", {}));
    }
  }

  private async fetchUpdates(fetchedAny: boolean = false) {
    const allNewsletters = await library().getAllNewsletters();
    if (allNewsletters.length === 0) {
      return;
    }

    const newestNewsletter = allNewsletters.sort(compareNewslettersForApi)[0];
    const { data } = await axios.get<APINewsletters>("/newsletters", {
      signal: this.abortController!.signal,
      headers: { Authorization: `Bearer ${this.authToken}` },
      params: {
        after_timestamp: newestNewsletter.updatedAt,
        after_id: newestNewsletter.id,
      },
    });

    for (const newsletter of this.transformResponse(
      data,
      this.buildOriginalNewslettersMap(allNewsletters, data),
    )) {
      await library().putNewsletter(newsletter);
    }

    if (data.result.length > 0) {
      await this.fetchUpdates(true);
    } else if (fetchedAny) {
      postMessage(buildWorkerMessage("newsletters updated", {}));
    }
  }

  private buildOriginalNewslettersMap(
    allNewsletters: Newsletter[],
    data: APINewsletters,
  ): Map<number, Newsletter> {
    const newNewsletters = data.result.reduce((set, n) => {
      set.add(n.id);
      return set;
    }, new Set<number>());
    return allNewsletters.reduce((map, n) => {
      if (newNewsletters.has(n.id)) {
        map.set(n.id, n);
      }
      return map;
    }, new Map<number, Newsletter>());
  }

  private transformResponse(
    data: APINewsletters,
    originalNewsletters: Map<number, Newsletter> | null = null,
  ): Newsletter[] {
    return data.result.map((n) => {
      const original =
        originalNewsletters !== null ? originalNewsletters.get(n.id) : null;
      return {
        id: n.id,
        title: n.title,
        author: n.author,
        sourceMimeType: n.source_mime_type,
        read: n.read,
        deleted: n.deleted,
        progress: n.progress,
        createdAt: n.created_at,
        updatedAt: n.updated_at,
        epubUpdatedAt: n.epub_updated_at,
        epubVersion: original ? original.epubVersion : null,
        epubLastAccessedAt: original ? original.epubLastAccessedAt : null,
        sourceLastAccessedAt: original ? original.sourceLastAccessedAt : null,
      };
    });
  }
}
