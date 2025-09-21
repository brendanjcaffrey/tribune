import { describe, it, expect, vi, beforeEach } from "vitest";
import { SyncManager } from "../src/SyncManager";
import library, { Newsletter } from "../src/Library";
import axios, { GenericAbortSignal } from "axios";
import { ErrorMessage, NewslettersUpdated } from "../src/WorkerTypes";
import { DownloadManager } from "../src/DownloadManager";

vi.mock("axios", () => ({
  default: {
    get: vi.fn(),
  },
}));

vi.mock("../src/Library", () => {
  const MockLibrary = vi.fn();
  MockLibrary.prototype.setInitializedListener = vi.fn();
  MockLibrary.prototype.hasAnyNewsletters = vi.fn();
  MockLibrary.prototype.putNewsletter = vi.fn();
  MockLibrary.prototype.getAllNewsletters = vi.fn();

  const mockLibrary = new MockLibrary();
  return {
    default: vi.fn(() => mockLibrary),
  };
});

vi.mock("../src/Files", () => {
  return {
    files: vi.fn(),
  };
});

vi.stubGlobal("postMessage", vi.fn());

function mockHasAnyNewslettersResolve(hasAny: boolean) {
  vi.mocked(library().hasAnyNewsletters).mockImplementationOnce(() => {
    return Promise.resolve(hasAny);
  });
}

function mockGetAllNewslettersResolve(newsletters: Newsletter[]) {
  vi.mocked(library().getAllNewsletters).mockImplementationOnce(() => {
    return Promise.resolve(newsletters);
  });
}

function mockAxiosGetResolve<T>(data: T) {
  vi.mocked(axios.get).mockImplementationOnce(() => {
    return Promise.resolve({ data });
  });
}

function mockAxiosGetResolveAfterDelay<T>(data: T, delayMs: number) {
  vi.mocked(axios.get).mockImplementationOnce(() => {
    return new Promise((resolve) => {
      setTimeout(() => {
        resolve(data);
      }, delayMs);
    });
  });
}

class SyncManagerSpecError extends Error {
  code: string;

  constructor(message: string, code: string) {
    super(message);
    this.name = "SyncManagerSpecError";
    this.code = code;
  }
}
function mockAxiosGetError(code: string = "ERR_UNKNOWN") {
  vi.mocked(axios.get).mockImplementationOnce(() => {
    return Promise.reject(new SyncManagerSpecError("mock error", code));
  });
}

function expectPutNewsletterCall(newsletter: Newsletter) {
  expect(library().putNewsletter).toHaveBeenCalledTimes(1);
  expect(library().putNewsletter).toHaveBeenCalledWith(newsletter);
}

interface Request {
  path: string;
  params: object;
}
function expectAxiosGetCalls(requests: Request[]) {
  expect(axios.get).toHaveBeenCalledTimes(requests.length);
  requests.forEach((request) => {
    expect(axios.get).toHaveBeenCalledWith(
      request.path,
      expect.objectContaining({
        headers: expect.objectContaining({
          Authorization: "Bearer test-token",
        }),
        params: request.params,
      }),
    );
  });
  vi.mocked(axios.get).mockClear();
}

function expectNewsletterUpdatedMessage() {
  expect(postMessage).toHaveBeenCalledTimes(1);
  expect(postMessage).toHaveBeenCalledWith({
    type: "newsletters updated",
  } as NewslettersUpdated);
}

function expectErrorPostMessage() {
  expect(postMessage).toHaveBeenCalledTimes(1);
  expect(postMessage).toHaveBeenCalledWith({
    type: "error",
    error: "mock error",
  } as ErrorMessage);
}

const A1 = {
  id: 1,
  title: "t1",
  author: "a1",
  source_mime_type: "text/html",
  read: true,
  deleted: false,
  progress: "",
  created_at: "2025-01-01 06:00:01.456789+00",
  updated_at: "2025-01-02 06:00:01.456789+00",
  epub_updated_at: "2025-01-03 06:00:01.456789+00",
};
const N1 = {
  id: 1,
  title: "t1",
  author: "a1",
  sourceMimeType: "text/html",
  read: true,
  deleted: false,
  progress: "",
  createdAt: "2025-01-01 06:00:01.456789+00",
  updatedAt: "2025-01-02 06:00:01.456789+00",
  epubUpdatedAt: "2025-01-03 06:00:01.456789+00",
  epubVersion: null,
  epubLastAccessedAt: null,
  sourceLastAccessedAt: null,
};
const N2 = {
  id: 2,
  title: "t2",
  author: "a2",
  sourceMimeType: "text/html",
  read: true,
  deleted: false,
  progress: "",
  createdAt: "2025-01-01 06:00:01.456789+00",
  updatedAt: "2025-01-20 06:00:01.456789+00",
  epubUpdatedAt: "2025-01-03 06:00:01.456789+00",
  epubVersion: null,
  epubLastAccessedAt: null,
  sourceLastAccessedAt: null,
};
const N3 = {
  id: 3,
  title: "t3",
  author: "a3",
  sourceMimeType: "text/html",
  read: true,
  deleted: false,
  progress: "",
  createdAt: "2025-01-01 06:00:01.456789+00",
  updatedAt: "2025-01-02 06:00:01.456789+00",
  epubUpdatedAt: "2025-01-03 06:00:01.456789+00",
  epubVersion: null,
  epubLastAccessedAt: null,
  sourceLastAccessedAt: null,
};
const A4 = {
  id: 4,
  title: "t4",
  author: "a4",
  source_mime_type: "text/html",
  read: true,
  deleted: false,
  progress: "",
  created_at: "2025-01-01 06:00:01.456789+00",
  updated_at: "2025-01-25 06:00:01.456789+00",
  epub_updated_at: "2025-01-03 06:00:01.456789+00",
};
const N4 = {
  id: 4,
  title: "t4",
  author: "a4",
  sourceMimeType: "text/html",
  read: true,
  deleted: false,
  progress: "",
  createdAt: "2025-01-01 06:00:01.456789+00",
  updatedAt: "2025-01-25 06:00:01.456789+00",
  epubUpdatedAt: "2025-01-03 06:00:01.456789+00",
  epubVersion: null,
  epubLastAccessedAt: null,
  sourceLastAccessedAt: null,
};

const N5_init = {
  id: 5,
  title: "t5",
  author: "a5",
  sourceMimeType: "text/html",
  read: false,
  deleted: false,
  progress: "",
  createdAt: "2025-01-01 06:00:01.456789+00",
  updatedAt: "2025-01-25 06:00:01.456789+00",
  epubUpdatedAt: "2025-01-03 06:00:01.456789+00",
  epubVersion: "2025-01-03 06:00:01.456789+00",
  epubLastAccessedAt: null,
  sourceLastAccessedAt: null,
};
const A5 = {
  id: 5,
  title: "t5_",
  author: "a5_",
  source_mime_type: "text/html",
  read: true,
  deleted: false,
  progress: "",
  created_at: "2025-01-01 06:00:01.456789+00",
  updated_at: "2025-01-26 06:00:01.456789+00",
  epub_updated_at: "2025-01-03 06:00:01.456789+00",
};
const N5_updated = {
  id: 5,
  title: "t5_",
  author: "a5_",
  sourceMimeType: "text/html",
  read: true,
  deleted: false,
  progress: "",
  createdAt: "2025-01-01 06:00:01.456789+00",
  updatedAt: "2025-01-26 06:00:01.456789+00",
  epubUpdatedAt: "2025-01-03 06:00:01.456789+00",
  epubVersion: "2025-01-03 06:00:01.456789+00",
  epubLastAccessedAt: null,
  sourceLastAccessedAt: null,
};

describe("SyncManager", () => {
  const downloadManager = new DownloadManager();
  let syncManager: SyncManager;

  beforeEach(() => {
    downloadManager.checkForDownloads = vi.fn();
    syncManager = new SyncManager(downloadManager);

    vi.useFakeTimers();
    vi.resetAllMocks();
  });

  it("should sync without params when the library is empty", async () => {
    mockHasAnyNewslettersResolve(false);
    mockAxiosGetResolve({
      meta: {},
      result: [A1],
    });

    await syncManager.setLibraryInitialized();
    await syncManager.setAuthToken("test-token");

    expectAxiosGetCalls([{ path: "/newsletters", params: {} }]);
    expectPutNewsletterCall(N1);
    expectNewsletterUpdatedMessage();
    expect(vi.mocked(downloadManager.checkForDownloads)).toHaveBeenCalledOnce();
  });

  it("should attempt to sync with the latest id/updated at", async () => {
    mockHasAnyNewslettersResolve(true);
    mockGetAllNewslettersResolve([N1, N2, N3]);
    mockGetAllNewslettersResolve([N1, N2, N3, N4]);

    mockAxiosGetResolve({
      meta: {},
      result: [A4],
    });
    mockAxiosGetResolve({ meta: {}, result: [] });

    await syncManager.setLibraryInitialized();
    await syncManager.setAuthToken("test-token");

    expectAxiosGetCalls([
      {
        path: "/newsletters",
        params: {
          after_id: 2,
          after_timestamp: "2025-01-20 06:00:01.456789+00",
        },
      },
      {
        path: "/newsletters",
        params: {
          after_id: 4,
          after_timestamp: "2025-01-25 06:00:01.456789+00",
        },
      },
    ]);

    expectPutNewsletterCall(N4);
    expectNewsletterUpdatedMessage();
    expect(vi.mocked(downloadManager.checkForDownloads)).toHaveBeenCalledOnce();
  });

  it("should overwrite updated newsletters but keep the epubVersion field", async () => {
    mockHasAnyNewslettersResolve(true);
    mockGetAllNewslettersResolve([N5_init]);
    mockGetAllNewslettersResolve([N5_updated]);

    mockAxiosGetResolve({
      meta: {},
      result: [A5],
    });
    mockAxiosGetResolve({ meta: {}, result: [] });

    await syncManager.setLibraryInitialized();
    await syncManager.setAuthToken("test-token");

    expectAxiosGetCalls([
      {
        path: "/newsletters",
        params: {
          after_id: 5,
          after_timestamp: "2025-01-25 06:00:01.456789+00",
        },
      },
      {
        path: "/newsletters",
        params: {
          after_id: 5,
          after_timestamp: "2025-01-26 06:00:01.456789+00",
        },
      },
    ]);

    expectPutNewsletterCall(N5_updated);
    expectNewsletterUpdatedMessage();
    expect(vi.mocked(downloadManager.checkForDownloads)).toHaveBeenCalledOnce();
  });

  it("should post an error when the sync request fails", async () => {
    mockHasAnyNewslettersResolve(false);
    mockAxiosGetError();

    await syncManager.setLibraryInitialized();
    await syncManager.setAuthToken("test-token");
    expectAxiosGetCalls([{ path: "/newsletters", params: {} }]);
    expectErrorPostMessage();
    expect(vi.mocked(downloadManager.checkForDownloads)).not.toHaveBeenCalled();
  });

  it("should cancel pending requests if the auth token is cleared", async () => {
    mockHasAnyNewslettersResolve(false);
    mockAxiosGetResolveAfterDelay(
      {
        meta: {},
        result: [A1],
      },
      100,
    );

    await syncManager.setLibraryInitialized();
    const promise = syncManager.setAuthToken("test-token");
    await vi.waitFor(() => {
      if (vi.mocked(axios.get).mock.calls.length === 0) {
        throw new Error("no axios.get call yet");
      }
    });

    const signal: GenericAbortSignal = vi.mocked(axios.get).mock.calls[0][1]!
      .signal!;
    expect(signal.aborted).toBe(false);

    syncManager.clearAuthToken();
    await vi.advanceTimersToNextTimerAsync();
    await promise;

    expectAxiosGetCalls([{ path: "/newsletters", params: {} }]);
    expect(library().putNewsletter).toHaveBeenCalledTimes(0);
    expect(postMessage).toHaveBeenCalledTimes(0);
    expect(vi.mocked(downloadManager.checkForDownloads)).not.toHaveBeenCalled();
  });
});
