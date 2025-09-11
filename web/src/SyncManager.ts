import axios from "axios";
import { buildWorkerMessage, type MainToWorkerMessage } from "./WorkerTypes";
import library, { type Newsletter } from "./Library";
import { compareNewslettersForApi } from "./compareNewsletters";
import { type APINewsletters } from "./APINewsletters";

const REFRESH_MILLIS = 5 * 60 * 1000;

export class SyncManager {
  private syncInProgress: boolean = false;
  private authToken: string | null = null;
  private libraryInitialized: boolean = false;
  private timerId: number | null = null;

  public constructor() {
    library().setInitializedListener(() => {
      this.libraryInitialized = true;
      this.syncLibrary();
    });
  }

  public async setAuthToken(authToken: string | null) {
    this.authToken = authToken;
    await this.syncLibrary();
  }

  private async syncLibrary() {
    if (
      this.syncInProgress ||
      this.authToken === null ||
      !this.libraryInitialized
    ) {
      return;
    }

    if (this.timerId !== null) {
      clearInterval(this.timerId);
      this.timerId = null;
    }

    try {
      this.syncInProgress = true;
      if (await library().hasAnyNewsletters()) {
        await this.fetchUpdates();
      } else {
        await this.fetchInitial();
      }
    } catch (error) {
      console.error(error);
      if (error instanceof Error) {
        postMessage(buildWorkerMessage("error", { error: error.message }));
      } else {
        postMessage(buildWorkerMessage("error", { error: "unknown error" }));
      }
    } finally {
      this.syncInProgress = false;
      this.timerId = setTimeout(() => this.syncLibrary(), REFRESH_MILLIS);
    }
  }

  private async fetchInitial() {
    const { data } = await axios.get<APINewsletters>("/newsletters", {
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

const syncManager = new SyncManager();

onmessage = (ev: MessageEvent<MainToWorkerMessage>) => {
  const msg = ev.data;

  if (msg.type === "auth token") {
    syncManager.setAuthToken(msg.authToken);
  }
};
