import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import axios from "axios";
import qs from "qs";
import library, { Newsletter } from "../src/Library";
import { UpdateManager, Update, DB_KEY } from "../src/UpdateManager";

vi.stubGlobal("postMessage", vi.fn());
vi.mock("axios");
vi.mock("idb-keyval", () => {
  let store: Record<string, any> = {}; // eslint-disable-line @typescript-eslint/no-explicit-any
  return {
    get: vi.fn((key: string) => {
      return Promise.resolve(store[key]);
    }),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    set: vi.fn((key: string, value: any) => {
      store[key] = clone(value);
      return Promise.resolve();
    }),
    clear: () => {
      store = {};
    },
  };
});

import { get, set, clear } from "idb-keyval";
import { buildWorkerMessage } from "../src/WorkerTypes";
import { clone } from "lodash";

vi.mock("../src/Library", () => {
  const MockLibrary = vi.fn();
  MockLibrary.prototype.getNewsletter = vi.fn();
  MockLibrary.prototype.putNewsletter = vi.fn();

  const mockLibrary = new MockLibrary();
  return {
    default: vi.fn(() => mockLibrary),
  };
});

function expectLibraryPutNewsletterCall(newsletter: Newsletter) {
  expect(library().putNewsletter).toHaveBeenCalledOnce();
  expect(library().putNewsletter).toHaveBeenCalledWith(newsletter);
}

function expectNewslettersUpdatedPostMessage() {
  expect(postMessage).toHaveBeenCalledOnce();
  expect(postMessage).toHaveBeenCalledWith(
    buildWorkerMessage("newsletters updated", {}),
  );
}

function expectErrorPostMessage(msg: string) {
  expect(postMessage).toHaveBeenCalledOnce();
  expect(postMessage).toHaveBeenCalledWith(
    buildWorkerMessage("error", { error: expect.stringContaining(msg) }),
  );
}

function expectAxiosPutReadRequest(id: number) {
  expect(axios.put).toHaveBeenCalledWith(
    `/newsletters/${id}/read`,
    undefined,
    expect.objectContaining({
      headers: expect.objectContaining({
        Authorization: "Bearer mock-token",
      }),
    }),
  );
}

function expectAxiosPutUnreadRequest(id: number) {
  expect(axios.put).toHaveBeenCalledWith(
    `/newsletters/${id}/unread`,
    undefined,
    expect.objectContaining({
      headers: expect.objectContaining({
        Authorization: "Bearer mock-token",
      }),
    }),
  );
}

function expectAxiosDeleteRequest(id: number) {
  expect(axios.delete).toHaveBeenCalledWith(
    `/newsletters/${id}`,
    expect.objectContaining({
      headers: expect.objectContaining({
        Authorization: "Bearer mock-token",
      }),
    }),
  );
}

function expectAxiosPutProgressRequest(id: number, progress: string) {
  expect(axios.put).toHaveBeenCalledWith(
    `/newsletters/${id}/progress`,
    qs.stringify({ progress }),
    expect.objectContaining({
      headers: expect.objectContaining({
        Authorization: "Bearer mock-token",
      }),
    }),
  );
}

function clearAxiosMocks() {
  vi.mocked(axios.put).mockClear();
  vi.mocked(axios.delete).mockClear();
}

async function waitForUpdatesToFinish(manager: UpdateManager) {
  await vi.waitFor(() => {
    if (manager.isAttemptingBulkUpdates()) {
      throw new Error("still attempting");
    }
  });
}

function buildNewsletter(
  id: number,
  timestamp: string,
  read: boolean,
  deleted: boolean,
  progress: string,
): Newsletter {
  return {
    id,
    title: id.toString(),
    author: id.toString(),
    sourceMimeType: "index/html",
    read,
    deleted,
    progress,
    createdAt: timestamp,
    updatedAt: timestamp,
    epubUpdatedAt: timestamp,
    epubVersion: null,
    epubLastAccessedAt: null,
    sourceLastAccessedAt: null,
  };
}

describe("UpdateManager", () => {
  const HTTP_200 = { status: 200, statusText: "OK" };
  const HTTP_404 = { status: 404, statusText: "NOT FOUND" };

  // these get modified by tests, so need to be functions
  const NEWSLETTER_123_UNREAD = () =>
    buildNewsletter(
      123,
      "2025-01-01 06:00:01.456789+00",
      /*read=*/ false,
      /*deleted=*/ false,
      /*progress=*/ "",
    );

  const NEWSLETTER_123_READ = () =>
    buildNewsletter(
      123,
      "2025-01-01 06:00:01.456789+00",
      /*read=*/ true,
      /*deleted=*/ false,
      /*progress=*/ "",
    );

  const NEWSLETTER_123_DELETED = () =>
    buildNewsletter(
      123,
      "2025-01-01 06:00:01.456789+00",
      /*read=*/ false,
      /*deleted=*/ true,
      /*progress=*/ "",
    );

  const NEWSLETTER_123_PROGRESS = () =>
    buildNewsletter(
      123,
      "2025-01-01 06:00:01.456789+00",
      /*read=*/ false,
      /*deleted=*/ false,
      /*progress=*/ "hi",
    );

  const READ_UPDATE: Update = {
    type: "read",
    newsletterId: 123,
  };

  const UNREAD_UPDATE: Update = {
    type: "unread",
    newsletterId: 123,
  };

  const DELETE_UPDATE: Update = {
    type: "delete",
    newsletterId: 123,
  };

  const PROGRESS_UPDATE: Update = {
    type: "progress",
    newsletterId: 123,
    progress: "hi",
  };

  beforeEach(() => {
    vi.useFakeTimers();
    vi.clearAllMocks();
    vi.clearAllTimers();
    clear();
  });

  afterEach(() => {
    vi.restoreAllMocks();
    vi.clearAllTimers();
    clear();
  });

  it("should initialize with no pending updates if db key doesn't exist", async () => {
    const manager = new UpdateManager();
    expect(manager.getPendingUpdates()).toEqual([]);
    expect(await get(DB_KEY)).toBeUndefined();
  });

  it("should do nothing on auth token set & library initialized set if there's nothing pending", async () => {
    const manager = new UpdateManager();
    await manager.setAuthToken("mock-token");
    await manager.setLibraryInitialized();
    expect(axios.put).not.toHaveBeenCalled();
  });

  describe("read", () => {
    it("should initialize with pending read updates from db if they exist", async () => {
      set(DB_KEY, [READ_UPDATE]);
      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      expect(manager.getPendingUpdates()).toEqual([READ_UPDATE]);
    });

    it("should post an error if the library isn't initialized when trying to make a read update", async () => {
      const manager = new UpdateManager();
      await manager.markNewsletterAsRead(123);
      expectErrorPostMessage("can't mark read");
    });

    it("should attempt any pending read updates when the auth token & library initialized is set", async () => {
      set(DB_KEY, [READ_UPDATE]);
      vi.mocked(axios.put).mockResolvedValueOnce(HTTP_200);

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();
      expectAxiosPutReadRequest(123);
    });

    it("should add a read update to pending updates & persist if not authenticated", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_UNREAD(),
      );

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setLibraryInitialized();
      await manager.markNewsletterAsRead(123);

      expect(manager.getPendingUpdates()).toEqual([READ_UPDATE]);
      expect(await get(DB_KEY)).toEqual([READ_UPDATE]);
      expectLibraryPutNewsletterCall(NEWSLETTER_123_READ());
      expectNewslettersUpdatedPostMessage();
    });

    it("should immediately attempt a read update if authenticated", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_UNREAD(),
      );
      vi.mocked(axios.put).mockResolvedValueOnce(HTTP_200);

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();

      await manager.markNewsletterAsRead(123);

      expectLibraryPutNewsletterCall(NEWSLETTER_123_READ());
      expectNewslettersUpdatedPostMessage();
      expectAxiosPutReadRequest(123);

      expect(manager.getPendingUpdates()).toEqual([]);
      expect(await get(DB_KEY)).toBeUndefined();
    });

    it("should retry sending pending read updates on a timer", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_UNREAD(),
      );

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();

      // fails on first attempt
      vi.mocked(axios.put).mockRejectedValueOnce(new Error("Network error"));
      await manager.markNewsletterAsRead(123);
      expectLibraryPutNewsletterCall(NEWSLETTER_123_READ());
      expectNewslettersUpdatedPostMessage();
      expect(manager.getPendingUpdates()).toEqual([READ_UPDATE]);
      expect(await get(DB_KEY)).toEqual([READ_UPDATE]);
      expectAxiosPutReadRequest(123);
      clearAxiosMocks();

      // fails on second attempt
      vi.mocked(axios.put).mockRejectedValueOnce(new Error("Server error"));
      vi.runOnlyPendingTimers();
      await waitForUpdatesToFinish(manager);
      expect(manager.getPendingUpdates()).toEqual([READ_UPDATE]);
      expect(await get(DB_KEY)).toEqual([READ_UPDATE]);
      expectAxiosPutReadRequest(123);
      clearAxiosMocks();

      // succeeds on third attempt
      vi.mocked(axios.put).mockResolvedValueOnce(HTTP_200);
      vi.runOnlyPendingTimers();
      await waitForUpdatesToFinish(manager);

      expectAxiosPutReadRequest(123);
      expect(manager.getPendingUpdates()).toEqual([]);
      expect(await get(DB_KEY)).toEqual([]);
    });

    it("should drop read updates on a 404", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_UNREAD(),
      );

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();

      // fails on first attempt
      vi.mocked(axios.put).mockResolvedValueOnce(HTTP_404);
      await manager.markNewsletterAsRead(123);
      expectLibraryPutNewsletterCall(NEWSLETTER_123_READ());
      expectNewslettersUpdatedPostMessage();
      expect(manager.getPendingUpdates()).toEqual([]);
      expect(await get(DB_KEY)).toBeUndefined();
    });
  });

  describe("unread", () => {
    it("should initialize with pending unread updates from db if they exist", async () => {
      set(DB_KEY, [UNREAD_UPDATE]);
      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      expect(manager.getPendingUpdates()).toEqual([UNREAD_UPDATE]);
    });

    it("should post an error if the library isn't initialized when trying to make an uread update", async () => {
      const manager = new UpdateManager();
      await manager.markNewsletterAsUnread(123);
      expectErrorPostMessage("can't mark unread");
    });

    it("should attempt any pending unread updates when the auth token & library initialized is set", async () => {
      set(DB_KEY, [UNREAD_UPDATE]);
      vi.mocked(axios.put).mockResolvedValueOnce(HTTP_200);

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();
      expectAxiosPutUnreadRequest(123);
    });

    it("should add an unread update to pending updates & persist if not authenticated", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_READ(),
      );

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setLibraryInitialized();
      await manager.markNewsletterAsUnread(123);

      expect(manager.getPendingUpdates()).toEqual([UNREAD_UPDATE]);
      expect(await get(DB_KEY)).toEqual([UNREAD_UPDATE]);
      expectLibraryPutNewsletterCall(NEWSLETTER_123_UNREAD());
      expectNewslettersUpdatedPostMessage();
    });

    it("should immediately attempt an unread update if authenticated", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_READ(),
      );
      vi.mocked(axios.put).mockResolvedValueOnce(HTTP_200);

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();

      await manager.markNewsletterAsUnread(123);

      expectLibraryPutNewsletterCall(NEWSLETTER_123_UNREAD());
      expectNewslettersUpdatedPostMessage();
      expectAxiosPutUnreadRequest(123);

      expect(manager.getPendingUpdates()).toEqual([]);
      expect(await get(DB_KEY)).toBeUndefined();
    });

    it("should retry sending pending unread updates on a timer", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_READ(),
      );

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();

      // fails on first attempt
      vi.mocked(axios.put).mockRejectedValueOnce(new Error("Network error"));
      await manager.markNewsletterAsUnread(123);
      expectLibraryPutNewsletterCall(NEWSLETTER_123_UNREAD());
      expectNewslettersUpdatedPostMessage();
      expect(manager.getPendingUpdates()).toEqual([UNREAD_UPDATE]);
      expect(await get(DB_KEY)).toEqual([UNREAD_UPDATE]);
      expectAxiosPutUnreadRequest(123);
      clearAxiosMocks();

      // fails on second attempt
      vi.mocked(axios.put).mockRejectedValueOnce(new Error("Server error"));
      vi.runOnlyPendingTimers();
      await waitForUpdatesToFinish(manager);
      expect(manager.getPendingUpdates()).toEqual([UNREAD_UPDATE]);
      expect(await get(DB_KEY)).toEqual([UNREAD_UPDATE]);
      expectAxiosPutUnreadRequest(123);
      clearAxiosMocks();

      // succeeds on third attempt
      vi.mocked(axios.put).mockResolvedValueOnce(HTTP_200);
      vi.runOnlyPendingTimers();
      await waitForUpdatesToFinish(manager);

      expectAxiosPutUnreadRequest(123);
      expect(manager.getPendingUpdates()).toEqual([]);
      expect(await get(DB_KEY)).toEqual([]);
    });

    it("should drop unread updates on a 404", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_READ(),
      );

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();

      // fails on first attempt
      vi.mocked(axios.put).mockResolvedValueOnce(HTTP_404);
      await manager.markNewsletterAsUnread(123);
      expectLibraryPutNewsletterCall(NEWSLETTER_123_UNREAD());
      expectNewslettersUpdatedPostMessage();
      expect(manager.getPendingUpdates()).toEqual([]);
      expect(await get(DB_KEY)).toBeUndefined();
    });
  });

  describe("delete", () => {
    it("should initialize with pending delete updates from db if they exist", async () => {
      set(DB_KEY, [DELETE_UPDATE]);
      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      expect(manager.getPendingUpdates()).toEqual([DELETE_UPDATE]);
    });

    it("should post an error if the library isn't initialized when trying to make an uread update", async () => {
      const manager = new UpdateManager();
      await manager.markNewsletterAsDeleted(123);
      expectErrorPostMessage("can't delete");
    });

    it("should attempt any pending delete updates when the auth token & library initialized is set", async () => {
      set(DB_KEY, [DELETE_UPDATE]);
      vi.mocked(axios.delete).mockResolvedValueOnce(HTTP_200);

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();
      expectAxiosDeleteRequest(123);
    });

    it("should add a delete update to pending updates & persist if not authenticated", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_UNREAD(),
      );

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setLibraryInitialized();
      await manager.markNewsletterAsDeleted(123);

      expect(manager.getPendingUpdates()).toEqual([DELETE_UPDATE]);
      expect(await get(DB_KEY)).toEqual([DELETE_UPDATE]);
      expectLibraryPutNewsletterCall(NEWSLETTER_123_DELETED());
      expectNewslettersUpdatedPostMessage();
    });

    it("should immediately attempt a delete update if authenticated", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_UNREAD(),
      );

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();
      vi.mocked(axios.delete).mockResolvedValueOnce(HTTP_200);

      await manager.markNewsletterAsDeleted(123);

      expectLibraryPutNewsletterCall(NEWSLETTER_123_DELETED());
      expectNewslettersUpdatedPostMessage();
      expectAxiosDeleteRequest(123);

      expect(manager.getPendingUpdates()).toEqual([]);
      expect(await get(DB_KEY)).toBeUndefined();
    });

    it("should retry sending pending delete updates on a timer", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_UNREAD(),
      );

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();

      // fails on first attempt
      vi.mocked(axios.delete).mockRejectedValueOnce(new Error("Network error"));
      await manager.markNewsletterAsDeleted(123);
      expectLibraryPutNewsletterCall(NEWSLETTER_123_DELETED());
      expectNewslettersUpdatedPostMessage();
      expect(manager.getPendingUpdates()).toEqual([DELETE_UPDATE]);
      expect(await get(DB_KEY)).toEqual([DELETE_UPDATE]);
      expectAxiosDeleteRequest(123);
      clearAxiosMocks();

      // fails on second attempt
      vi.mocked(axios.delete).mockRejectedValueOnce(new Error("Server error"));
      vi.runOnlyPendingTimers();
      await waitForUpdatesToFinish(manager);
      expect(manager.getPendingUpdates()).toEqual([DELETE_UPDATE]);
      expect(await get(DB_KEY)).toEqual([DELETE_UPDATE]);
      expectAxiosDeleteRequest(123);
      clearAxiosMocks();

      // succeeds on third attempt
      vi.mocked(axios.delete).mockResolvedValueOnce(HTTP_200);
      vi.runOnlyPendingTimers();
      await waitForUpdatesToFinish(manager);

      expectAxiosDeleteRequest(123);
      expect(manager.getPendingUpdates()).toEqual([]);
      expect(await get(DB_KEY)).toEqual([]);
    });

    it("should drop delete updates on a 404", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_UNREAD(),
      );

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();

      // fails on first attempt
      vi.mocked(axios.delete).mockResolvedValueOnce(HTTP_404);
      await manager.markNewsletterAsDeleted(123);
      expectLibraryPutNewsletterCall(NEWSLETTER_123_DELETED());
      expectNewslettersUpdatedPostMessage();
      expect(manager.getPendingUpdates()).toEqual([]);
      expect(await get(DB_KEY)).toBeUndefined();
    });
  });

  describe("progress", () => {
    it("should initialize with pending progress updates from db if they exist", async () => {
      set(DB_KEY, [PROGRESS_UPDATE]);
      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      expect(manager.getPendingUpdates()).toEqual([PROGRESS_UPDATE]);
    });

    it("should post an error if the library isn't initialized when trying to make an uread update", async () => {
      const manager = new UpdateManager();
      await manager.updateNewsletterProgress(123, "hi");
      expectErrorPostMessage("can't update progress");
    });

    it("should attempt any pending progress updates when the auth token & library initialized is set", async () => {
      set(DB_KEY, [PROGRESS_UPDATE]);
      vi.mocked(axios.put).mockResolvedValueOnce(HTTP_200);

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();
      expectAxiosPutProgressRequest(123, "hi");
    });

    it("should add a progress update to pending updates & persist if not authenticated", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_UNREAD(),
      );

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setLibraryInitialized();
      await manager.updateNewsletterProgress(123, "hi");

      expect(manager.getPendingUpdates()).toEqual([PROGRESS_UPDATE]);
      expect(await get(DB_KEY)).toEqual([PROGRESS_UPDATE]);
      expectLibraryPutNewsletterCall(NEWSLETTER_123_PROGRESS());
      expectNewslettersUpdatedPostMessage();
    });

    it("should immediately attempt a progress update if authenticated", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_UNREAD(),
      );
      vi.mocked(axios.put).mockResolvedValueOnce(HTTP_200);

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();

      await manager.updateNewsletterProgress(123, "hi");

      expectLibraryPutNewsletterCall(NEWSLETTER_123_PROGRESS());
      expectNewslettersUpdatedPostMessage();
      expectAxiosPutProgressRequest(123, "hi");

      expect(manager.getPendingUpdates()).toEqual([]);
      expect(await get(DB_KEY)).toBeUndefined();
    });

    it("should retry sending pending progress updates on a timer", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_UNREAD(),
      );

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();

      // fails on first attempt
      vi.mocked(axios.put).mockRejectedValueOnce(new Error("Network error"));
      await manager.updateNewsletterProgress(123, "hi");
      expectLibraryPutNewsletterCall(NEWSLETTER_123_PROGRESS());
      expectNewslettersUpdatedPostMessage();
      expect(manager.getPendingUpdates()).toEqual([PROGRESS_UPDATE]);
      expect(await get(DB_KEY)).toEqual([PROGRESS_UPDATE]);
      expectAxiosPutProgressRequest(123, "hi");
      clearAxiosMocks();

      // fails on second attempt
      vi.mocked(axios.put).mockRejectedValueOnce(new Error("Server error"));
      vi.runOnlyPendingTimers();
      await waitForUpdatesToFinish(manager);
      expect(manager.getPendingUpdates()).toEqual([PROGRESS_UPDATE]);
      expect(await get(DB_KEY)).toEqual([PROGRESS_UPDATE]);
      expectAxiosPutProgressRequest(123, "hi");
      clearAxiosMocks();

      // succeeds on third attempt
      vi.mocked(axios.put).mockResolvedValueOnce(HTTP_200);
      vi.runOnlyPendingTimers();
      await waitForUpdatesToFinish(manager);

      expectAxiosPutProgressRequest(123, "hi");
      expect(manager.getPendingUpdates()).toEqual([]);
      expect(await get(DB_KEY)).toEqual([]);
    });

    it("should drop progress updates on a 404", async () => {
      vi.mocked(library().getNewsletter).mockResolvedValueOnce(
        NEWSLETTER_123_UNREAD(),
      );

      const manager = new UpdateManager();
      await vi.waitUntil(() => manager.getPendingUpdatesFetched());
      await manager.setAuthToken("mock-token");
      await manager.setLibraryInitialized();

      // fails on first attempt
      vi.mocked(axios.put).mockResolvedValueOnce(HTTP_404);
      await manager.updateNewsletterProgress(123, "hi");
      expectLibraryPutNewsletterCall(NEWSLETTER_123_PROGRESS());
      expectNewslettersUpdatedPostMessage();
      expect(manager.getPendingUpdates()).toEqual([]);
      expect(await get(DB_KEY)).toBeUndefined();
    });
  });

  it("should support intermittent failing requests and adding while attempting updates", async () => {
    vi.mocked(library().getNewsletter).mockResolvedValueOnce(
      buildNewsletter(
        321,
        "2025-01-01 06:00:01.456789+00",
        /*read=*/ false,
        /*deleted=*/ false,
        /*progress=*/ "",
      ),
    );

    const updates: Update[] = [
      { type: "read", newsletterId: 123 },
      { type: "unread", newsletterId: 456 },
      { type: "delete", newsletterId: 789 },
    ];
    await set(DB_KEY, updates);
    updates.push({ type: "progress", newsletterId: 321, progress: "hi" });

    const manager = new UpdateManager();
    await vi.waitUntil(() => manager.getPendingUpdatesFetched());

    // first attempt: only 456 succeeds
    vi.mocked(axios.put).mockRejectedValueOnce(new Error("Network error"));
    vi.mocked(axios.put).mockResolvedValueOnce(HTTP_200);
    vi.mocked(axios.delete).mockRejectedValueOnce(new Error("Network error"));
    vi.mocked(axios.put).mockRejectedValueOnce(new Error("Network error"));
    manager.setAuthToken("mock-token");
    manager.setLibraryInitialized();
    await manager.updateNewsletterProgress(321, "hi");
    await waitForUpdatesToFinish(manager);

    expectLibraryPutNewsletterCall(
      buildNewsletter(
        321,
        "2025-01-01 06:00:01.456789+00",
        /*read=*/ false,
        /*deleted=*/ false,
        /*progress=*/ "hi",
      ),
    );
    expectNewslettersUpdatedPostMessage();

    expectAxiosPutReadRequest(123);
    expectAxiosPutUnreadRequest(456);
    expectAxiosDeleteRequest(789);
    expectAxiosPutProgressRequest(321, "hi");
    clearAxiosMocks();

    expect(await get(DB_KEY)).toEqual([updates[0], updates[2], updates[3]]);
    expect(manager.getPendingUpdates()).toEqual([
      updates[0],
      updates[2],
      updates[3],
    ]);

    // second attempt: only 321 succeeds
    vi.mocked(axios.put).mockRejectedValueOnce(new Error("Network error"));
    vi.mocked(axios.delete).mockRejectedValueOnce(new Error("Network error"));
    vi.mocked(axios.put).mockResolvedValueOnce(HTTP_200);
    manager.setAuthToken("mock-token");
    await waitForUpdatesToFinish(manager);
    expectAxiosPutReadRequest(123);
    expectAxiosDeleteRequest(789);
    expectAxiosPutProgressRequest(321, "hi");
    clearAxiosMocks();
    expect(await get(DB_KEY)).toEqual([updates[0], updates[2]]);
    expect(manager.getPendingUpdates()).toEqual([updates[0], updates[2]]);

    // third attempt: only 123 succeeds
    vi.mocked(axios.put).mockResolvedValueOnce(HTTP_200);
    vi.mocked(axios.delete).mockRejectedValueOnce(new Error("Network error"));
    manager.setAuthToken("mock-token");
    await waitForUpdatesToFinish(manager);
    expectAxiosPutReadRequest(123);
    expectAxiosDeleteRequest(789);
    clearAxiosMocks();
    expect(await get(DB_KEY)).toEqual([updates[2]]);
    expect(manager.getPendingUpdates()).toEqual([updates[2]]);

    // fourth attempt: 789 succeeds
    vi.mocked(axios.delete).mockResolvedValueOnce(HTTP_200);
    manager.setAuthToken("mock-token");
    await waitForUpdatesToFinish(manager);
    expectAxiosDeleteRequest(789);
    clearAxiosMocks();
    expect(await get(DB_KEY)).toEqual([]);
    expect(manager.getPendingUpdates()).toEqual([]);
  });
});
