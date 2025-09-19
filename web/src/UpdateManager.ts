import axios from "axios";
import { get, set } from "idb-keyval";
import { buildWorkerMessage } from "./WorkerTypes";
import library from "./Library";

export const DB_KEY = "updates";
const RETRY_MILLIS = 30000;

type MarkReadUpdate = {
  type: "read";
  newsletterId: number;
};

type MarkUnreadUpdate = {
  type: "unread";
  newsletterId: number;
};

export type Update = MarkReadUpdate | MarkUnreadUpdate;

export class UpdateManager {
  private libraryInitialized: boolean = false;
  private authToken: string | null = null;
  private pendingUpdatesFetched: boolean = false;
  private pendingUpdates: Update[] = [];
  private attemptingBulkUpdates: boolean = false;
  private timerHandler: NodeJS.Timeout | undefined = undefined;

  constructor() {
    get(DB_KEY).then((stored) => {
      this.pendingUpdates = Array.isArray(stored) ? stored : [];
      this.pendingUpdatesFetched = true;
      this.attemptUpdates();
    });
  }

  public isAttemptingBulkUpdates() {
    return this.attemptingBulkUpdates;
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
    if (!newsletter) {
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
    if (!newsletter) {
      return;
    }

    newsletter.read = false;
    await library().putNewsletter(newsletter);
    postMessage(buildWorkerMessage("newsletters updated", {}));

    await this.handleUpdate({ type: "unread", newsletterId });
  }

  private async handleUpdate(update: Update) {
    if (
      this.libraryInitialized &&
      this.authToken &&
      !this.attemptingBulkUpdates
    ) {
      try {
        await this.attemptUpdate(update);
      } catch (e) {
        console.error(`unable to handle ${update.type} update`, e);
        await this.addPendingUpdate(update);
      }
    } else {
      await this.addPendingUpdate(update);
    }
  }

  private async addPendingUpdate(update: Update) {
    this.pendingUpdates.push(update);
    await this.persistUpdates();
    this.setTimer();
  }

  private async attemptUpdate(update: Update) {
    const requestPath = `/newsletters/${update.newsletterId}/${update.type}`;
    const { status, statusText } = await axios.put(requestPath, undefined, {
      headers: {
        Authorization: `Bearer ${this.authToken}`,
      },
    });
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
      this.attemptingBulkUpdates ||
      this.pendingUpdates.length === 0
    ) {
      return;
    }

    this.attemptingBulkUpdates = true;
    let updateIndex = 0;
    while (updateIndex < this.pendingUpdates.length) {
      try {
        const update = this.pendingUpdates[updateIndex];
        await this.attemptUpdate(update);
        this.pendingUpdates.splice(updateIndex, 1);
      } catch (e) {
        console.error(
          "unable to send update",
          this.pendingUpdates[updateIndex],
          e,
        );
        updateIndex++;
      }
      this.persistUpdates();
    }

    this.attemptingBulkUpdates = false;
    this.setTimer();
  }

  async persistUpdates() {
    try {
      await set(DB_KEY, this.pendingUpdates);
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
