import axios from "axios";
import qs from "qs";
import { del, get, set } from "idb-keyval";
import { buildWorkerMessage } from "./WorkerTypes";
import library from "./Library";

export const DB_KEY = "updates";
const RETRY_MILLIS = 30_000;

type MarkReadUpdate = {
  type: "read";
  newsletterId: number;
};

type MarkUnreadUpdate = {
  type: "unread";
  newsletterId: number;
};

type DeleteUpdate = {
  type: "delete";
  newsletterId: number;
};

type ProgressUpdate = {
  type: "progress";
  newsletterId: number;
  progress: string;
};

export type Update =
  | MarkReadUpdate
  | MarkUnreadUpdate
  | DeleteUpdate
  | ProgressUpdate;

export class UpdateManager {
  private libraryInitialized: boolean = false;
  private authToken: string | null = null;
  private pendingUpdatesFetched: boolean = false;
  private pendingUpdates: Update[] = [];
  private flushing: boolean = false;
  private timerHandler: ReturnType<typeof setTimeout> | undefined = undefined;

  constructor() {
    get(DB_KEY).then((stored) => {
      this.pendingUpdates = Array.isArray(stored) ? stored : [];
      this.pendingUpdatesFetched = true;
      this.attemptUpdates();
    });

    if (typeof self !== "undefined" && "addEventListener" in self) {
      // offline -> online transitions retry the queue without waiting for the 30s timer.
      self.addEventListener("online", () => {
        this.attemptUpdates();
      });
    }
  }

  public isAttemptingBulkUpdates() {
    return this.flushing;
  }

  public getPendingUpdatesFetched(): boolean {
    return this.pendingUpdatesFetched;
  }

  public getPendingUpdates(): Update[] {
    return this.pendingUpdates;
  }

  public async setLibraryInitialized() {
    this.libraryInitialized = true;
    await this.attemptUpdates();
  }

  public async setAuthToken(authToken: string) {
    this.authToken = authToken;
    await this.attemptUpdates();
  }

  public async clearAuthToken() {
    this.authToken = null;
    this.pendingUpdates = [];
    await this.persistUpdates();
  }

  public async markNewsletterAsRead(newsletterId: number) {
    if (!this.libraryInitialized) {
      postMessage(
        buildWorkerMessage("error", {
          error: "can't mark read, library not initialized",
        }),
      );
      return;
    }

    const newsletter = await library().getNewsletter(newsletterId);
    if (!newsletter || newsletter.read) {
      return;
    }

    newsletter.read = true;
    await library().putNewsletter(newsletter);
    postMessage(buildWorkerMessage("newsletters updated", {}));

    await this.handleUpdate({ type: "read", newsletterId });
  }

  public async markNewsletterAsUnread(newsletterId: number) {
    if (!this.libraryInitialized) {
      postMessage(
        buildWorkerMessage("error", {
          error: "can't mark unread, library not initialized",
        }),
      );
      return;
    }

    const newsletter = await library().getNewsletter(newsletterId);
    if (!newsletter || !newsletter.read) {
      return;
    }

    newsletter.read = false;
    await library().putNewsletter(newsletter);
    postMessage(buildWorkerMessage("newsletters updated", {}));

    await this.handleUpdate({ type: "unread", newsletterId });
  }

  public async markNewsletterAsDeleted(newsletterId: number) {
    if (!this.libraryInitialized) {
      postMessage(
        buildWorkerMessage("error", {
          error: "can't delete newsletter, library not initialized",
        }),
      );
      return;
    }

    const newsletter = await library().getNewsletter(newsletterId);
    if (!newsletter || newsletter.deleted) {
      return;
    }

    newsletter.deleted = true;
    await library().putNewsletter(newsletter);
    postMessage(buildWorkerMessage("newsletters updated", {}));

    await this.handleUpdate({ type: "delete", newsletterId });
  }

  public async updateNewsletterProgress(
    newsletterId: number,
    progress: string,
  ) {
    if (!this.libraryInitialized) {
      postMessage(
        buildWorkerMessage("error", {
          error: "can't update progress, library not initialized",
        }),
      );
      return;
    }

    const newsletter = await library().getNewsletter(newsletterId);
    if (!newsletter || newsletter.progress === progress) {
      return;
    }

    newsletter.progress = progress;
    await library().putNewsletter(newsletter);
    postMessage(buildWorkerMessage("newsletters updated", {}));

    await this.handleUpdate({ type: "progress", newsletterId, progress });
  }

  private async handleUpdate(update: Update) {
    this.pendingUpdates.push(update);
    await this.persistUpdates();
    await this.attemptUpdates();
  }

  private async attemptUpdate(update: Update) {
    let status, statusText;
    const validateStatus = (status: number) => status == 200 || status == 404;
    if (update.type == "delete") {
      const requestPath = `/newsletters/${update.newsletterId}`;
      ({ status, statusText } = await axios.delete(requestPath, {
        headers: {
          Authorization: `Bearer ${this.authToken}`,
        },
        validateStatus,
      }));
    } else if (update.type == "progress") {
      const requestPath = `/newsletters/${update.newsletterId}/${update.type}`;
      const data = qs.stringify({ progress: update.progress });
      ({ status, statusText } = await axios.put(requestPath, data, {
        headers: {
          Authorization: `Bearer ${this.authToken}`,
        },
        validateStatus,
      }));
    } else {
      const requestPath = `/newsletters/${update.newsletterId}/${update.type}`;
      ({ status, statusText } = await axios.put(requestPath, undefined, {
        headers: {
          Authorization: `Bearer ${this.authToken}`,
        },
        validateStatus,
      }));
    }

    if (status == 404) {
      console.error(
        `got 404 for update (${update.type}/${update.newsletterId}), dropping it: ${update.type}`,
      );
    } else if (status != 200) {
      throw new Error(
        `Failed to send update (${update.type}/${update.newsletterId}): ${status} ${statusText}`,
      );
    }
  }

  private async attemptUpdates() {
    if (this.timerHandler) {
      clearTimeout(this.timerHandler);
      this.timerHandler = undefined;
    }

    if (
      !this.authToken ||
      !this.libraryInitialized ||
      !this.pendingUpdatesFetched ||
      this.flushing ||
      this.pendingUpdates.length === 0
    ) {
      return;
    }

    this.flushing = true;
    try {
      while (this.pendingUpdates.length > 0) {
        const update = this.pendingUpdates[0];
        try {
          await this.attemptUpdate(update);
          this.pendingUpdates.shift();
          await this.persistUpdates();
        } catch (e) {
          if (this.isPermanent(e)) {
            console.error("dropping update due to permanent error:", update, e);
            this.pendingUpdates.shift();
            await this.persistUpdates();
            continue;
          }
          // transient (network down, 5xx, 401 mid-renewal): stop the loop and rely on retry later
          console.error("unable to send update", update, e);
          break;
        }
      }
    } finally {
      this.flushing = false;
      this.setTimer();
    }
  }

  // permanent: a 4xx that won't get better with retries. skip 401 (might be
  // a transient mid-renewal failure) and 408 (literal timeout). read the
  // status off the response shape directly so we don't depend on axios's
  // `isAxiosError` helper, which is awkward under the test auto-mock.
  private isPermanent(error: unknown): boolean {
    const status = (error as { response?: { status?: number } })?.response
      ?.status;
    return (
      typeof status === "number" &&
      status >= 400 &&
      status < 500 &&
      status !== 401 &&
      status !== 408
    );
  }

  async persistUpdates() {
    try {
      if (this.pendingUpdates.length === 0) {
        await del(DB_KEY);
      } else {
        await set(DB_KEY, this.pendingUpdates);
      }
    } catch (error) {
      console.error("Failed to persist updates:", error);
    }
  }

  private setTimer() {
    if (
      !this.timerHandler &&
      this.pendingUpdates.length > 0 &&
      this.authToken
    ) {
      this.timerHandler = setTimeout(() => this.attemptUpdates(), RETRY_MILLIS);
    }
  }
}
