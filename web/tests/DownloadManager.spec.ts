import axios, { GenericAbortSignal } from "axios";
import { describe, it, expect, vi, beforeEach } from "vitest";
import { DownloadManager } from "../src/DownloadManager";
import library, { Newsletter } from "../src/Library";
import { files } from "../src/Files";
import { buildWorkerMessage, FileType } from "../src/WorkerTypes";
import { Mutex } from "async-mutex";

vi.stubGlobal("postMessage", vi.fn());
vi.mock("axios");

vi.mock("../src/Files", () => {
  const MockFiles = vi.fn();
  MockFiles.prototype.tryWriteFile = vi.fn();
  MockFiles.prototype.fileExists = vi.fn();
  MockFiles.prototype.tryDeleteFile = vi.fn();

  const mockFiles = new MockFiles();
  return {
    files: vi.fn(() => mockFiles),
  };
});

vi.mock("../src/Library", () => {
  const MockLibrary = vi.fn();
  MockLibrary.prototype.getNewsletters = vi.fn();
  MockLibrary.prototype.getAllNewsletters = vi.fn();
  MockLibrary.prototype.updateNewsletter = vi.fn();

  const mockLibrary = new MockLibrary();
  return {
    default: vi.fn(() => mockLibrary),
  };
});

function buildNewsletter(
  id: number,
  timestamp: string,
  read: boolean,
  deleted: boolean,
  epubVersion: string | null = null,
  epubLastAccessedAt: string | null = null,
  sourceLastAccessedAt: string | null = null,
): Newsletter {
  return {
    id,
    title: id.toString(),
    author: id.toString(),
    sourceMimeType: "index/html",
    read,
    deleted,
    progress: "",
    createdAt: timestamp,
    updatedAt: timestamp,
    epubUpdatedAt: timestamp,
    epubVersion,
    epubLastAccessedAt,
    sourceLastAccessedAt,
  };
}

function expectAxiosGetCall(id: number, type: FileType) {
  expect(axios.get).toHaveBeenCalledWith(
    `/newsletters/${id}/${type}`,
    expect.objectContaining({
      headers: expect.objectContaining({
        Authorization: "Bearer mock-token",
      }),
      responseType: "arraybuffer",
    }),
  );
}

describe("DownloadManager", () => {
  let downloadManager: DownloadManager;

  beforeEach(() => {
    downloadManager = new DownloadManager(new Mutex());
    vi.useFakeTimers();
    vi.resetAllMocks();
    // this is 2025-09-05T00:00:00.000Z, month is indexed to 0
    vi.setSystemTime(Date.UTC(2025, 8, 5, 0, 0, 0, 0));
  });

  it("if download mode is enabled, it should download any unread newsletters epubs, oldest first", async () => {
    const n1Buffer = new ArrayBuffer(10);
    const n2Buffer = new ArrayBuffer(20);
    vi.mocked(axios.get).mockResolvedValueOnce({ data: n1Buffer });
    vi.mocked(axios.get).mockResolvedValueOnce({ data: n2Buffer });

    vi.mocked(files().tryWriteFile).mockResolvedValueOnce(true);
    vi.mocked(files().tryWriteFile).mockResolvedValueOnce(true);

    const newsletters = [
      buildNewsletter(1, "2025-09-01 12:00:00.000000+00", false, false),
      buildNewsletter(2, "2025-09-02 12:00:00.000000+00", false, false),
      buildNewsletter(3, "2025-09-03 12:00:00.000000+00", true, false),
      buildNewsletter(4, "2025-09-04 12:00:00.000000+00", false, true),
    ];
    vi.mocked(library().getAllNewsletters).mockResolvedValue(newsletters);

    await downloadManager.setLibraryInitialized();
    await downloadManager.setDownloadMode(true);
    await downloadManager.setAuthToken("mock-token");

    expect(axios.get).toHaveBeenCalledTimes(2);
    expectAxiosGetCall(1, "epub");
    expectAxiosGetCall(2, "epub");

    expect(files().tryWriteFile).toHaveBeenCalledTimes(2);
    expect(files().tryWriteFile).toHaveBeenCalledWith("epub", 1, n1Buffer);
    expect(files().tryWriteFile).toHaveBeenCalledWith("epub", 2, n2Buffer);

    expect(library().updateNewsletter).toHaveBeenCalledTimes(2);
    const n1Update = vi.mocked(library().updateNewsletter).mock.calls[0];
    expect(n1Update[0]).toBe(1);
    expect(n1Update[1](newsletters[0])).toEqual({
      epubVersion: newsletters[0].epubUpdatedAt,
      epubLastAccessedAt: "2025-09-05T00:00:00.000Z",
    });
    const n2Update = vi.mocked(library().updateNewsletter).mock.calls[0];
    expect(n2Update[0]).toBe(1);
    expect(n2Update[1](newsletters[1])).toEqual({
      epubVersion: newsletters[1].epubUpdatedAt,
      epubLastAccessedAt: "2025-09-05T00:00:00.000Z",
    });

    expect(postMessage).toHaveBeenCalledTimes(5);
    expect(postMessage).toHaveBeenCalledWith(
      buildWorkerMessage("newsletters updated", {}),
    );
    expect(postMessage).toHaveBeenCalledWith(
      buildWorkerMessage("file download status", {
        id: 1,
        fileType: "epub",
        status: "done",
        receivedBytes: 10,
        totalBytes: 10,
      }),
    );
    expect(postMessage).toHaveBeenCalledWith(
      buildWorkerMessage("file fetched", {
        id: 1,
        fileType: "epub",
      }),
    );
    expect(postMessage).toHaveBeenCalledWith(
      buildWorkerMessage("file download status", {
        id: 2,
        fileType: "epub",
        status: "done",
        receivedBytes: 20,
        totalBytes: 20,
      }),
    );
    expect(postMessage).toHaveBeenCalledWith(
      buildWorkerMessage("file fetched", {
        id: 2,
        fileType: "epub",
      }),
    );
  });

  it("if download mode is disabled, it shouldn't download anything", async () => {
    const newsletters = [
      buildNewsletter(1, "2025-09-01 12:00:00.000000+00", false, false),
      buildNewsletter(2, "2025-09-02 12:00:00.000000+00", false, false),
      buildNewsletter(3, "2025-09-03 12:00:00.000000+00", true, false),
      buildNewsletter(4, "2025-09-04 12:00:00.000000+00", false, true),
    ];
    vi.mocked(library().getAllNewsletters).mockResolvedValue(newsletters);

    await downloadManager.setLibraryInitialized();
    await downloadManager.setDownloadMode(false);
    await downloadManager.setAuthToken("mock-token");

    expect(axios.get).toHaveBeenCalledTimes(0);
    expect(files().tryWriteFile).toHaveBeenCalledTimes(0);
    expect(library().updateNewsletter).toHaveBeenCalledTimes(0);
    expect(postMessage).toHaveBeenCalledTimes(0);
  });

  it("if download mode is enabled, it should download any unread epubs that have a new version", async () => {
    const n2Buffer = new ArrayBuffer(20);
    vi.mocked(axios.get).mockResolvedValueOnce({ data: n2Buffer });
    vi.mocked(files().tryWriteFile).mockResolvedValueOnce(true);

    const newsletters = [
      buildNewsletter(
        1,
        "2025-09-01 12:00:00.000000+00",
        false,
        false,
        "2025-09-01 12:00:00.000000+00", // epubVersion == epubLastUpdatedAt, no download needed
      ),
      buildNewsletter(
        2,
        "2025-09-02 12:00:00.000000+00",
        false,
        false,
        "2025-09-02 12:00:01.000000+00", // epubVersion != epubLastUpdatedAt, download needed
      ),
      buildNewsletter(
        3,
        "2025-09-03 12:00:00.000000+00",
        true,
        false,
        "2025-09-03 12:00:01.000000+00", // epubVersion != epubLastUpdatedAt but marked read, no download needed
      ),
      buildNewsletter(
        4,
        "2025-09-04 12:00:00.000000+00",
        false,
        true,
        "2025-09-04 12:00:01.000000+00", // epubVersion != epubLastUpdatedAt but deleted, no download needed
      ),
    ];
    vi.mocked(library().getAllNewsletters).mockResolvedValue(newsletters);

    await downloadManager.setLibraryInitialized();
    await downloadManager.setDownloadMode(true);
    await downloadManager.setAuthToken("mock-token");

    expect(axios.get).toHaveBeenCalledTimes(1);
    expectAxiosGetCall(2, "epub");

    expect(files().tryWriteFile).toHaveBeenCalledTimes(1);
    expect(files().tryWriteFile).toHaveBeenCalledWith("epub", 2, n2Buffer);

    expect(library().updateNewsletter).toHaveBeenCalledTimes(1);
    const n2Update = vi.mocked(library().updateNewsletter).mock.calls[0];
    expect(n2Update[0]).toBe(2);
    expect(n2Update[1](newsletters[1])).toEqual({
      epubVersion: newsletters[1].epubUpdatedAt,
      epubLastAccessedAt: "2025-09-05T00:00:00.000Z",
    });

    expect(postMessage).toHaveBeenCalledTimes(3);
    expect(postMessage).toHaveBeenCalledWith(
      buildWorkerMessage("newsletters updated", {}),
    );
    expect(postMessage).toHaveBeenCalledWith(
      buildWorkerMessage("file download status", {
        id: 2,
        fileType: "epub",
        status: "done",
        receivedBytes: 20,
        totalBytes: 20,
      }),
    );
    expect(postMessage).toHaveBeenCalledWith(
      buildWorkerMessage("file fetched", {
        id: 2,
        fileType: "epub",
      }),
    );
  });

  it("should stop immediately if the auth token is cleared", async () => {
    vi.mocked(axios.get).mockImplementationOnce(() => {
      return new Promise((_, reject) => {
        setTimeout(() => {
          reject("request canceled");
        }, 100);
      });
    });

    const newsletters = [
      buildNewsletter(1, "2025-09-01 12:00:00.000000+00", false, false),
      buildNewsletter(2, "2025-09-02 12:00:00.000000+00", false, false),
    ];
    vi.mocked(library().getAllNewsletters).mockResolvedValue(newsletters);

    await downloadManager.setLibraryInitialized();
    await downloadManager.setDownloadMode(true);
    downloadManager.setAuthToken("mock-token");

    await vi.waitUntil(() => vi.mocked(axios.get).mock.calls.length > 0);

    const signal: GenericAbortSignal = vi.mocked(axios.get).mock.calls[0][1]!
      .signal!;
    expect(signal.aborted).toBe(false);

    downloadManager.clearAuthToken();
    expect(signal.aborted).toBe(true);
    await vi.advanceTimersByTimeAsync(200);

    expect(axios.get).toHaveBeenCalledTimes(1);
    expectAxiosGetCall(1, "epub");

    expect(files().tryWriteFile).toHaveBeenCalledTimes(0);
    expect(library().updateNewsletter).toHaveBeenCalledTimes(0);
    expect(postMessage).toHaveBeenCalledTimes(0);
  });

  it("should delete epub & source files for deleted newsletters right away", async () => {
    vi.mocked(files().tryDeleteFile).mockResolvedValueOnce(true);
    vi.mocked(files().tryDeleteFile).mockResolvedValueOnce(true);

    const newsletters = [
      buildNewsletter(
        1,
        "2025-09-01 12:00:00.000000+00",
        false,
        false, // deleted = false, don't delete
        "2025-09-01 12:00:00.000000+00",
        "2025-09-05 12:00:00.000000+00",
        "2025-09-05 12:00:00.000000+00",
      ),
      buildNewsletter(
        2,
        "2025-09-02 12:00:00.000000+00",
        false,
        true, // delete = true, delete epub & source fiels
        "2025-09-02 12:00:01.000000+00",
        "2025-09-05 12:00:00.000000+00",
        "2025-09-05 12:00:00.000000+00",
      ),
    ];
    vi.mocked(library().getAllNewsletters).mockResolvedValue(newsletters);

    await downloadManager.setAuthToken("mock-token");
    await downloadManager.setLibraryInitialized();

    expect(files().tryDeleteFile).toHaveBeenCalledTimes(2);
    expect(files().tryDeleteFile).toHaveBeenCalledWith("epub", 2);
    expect(files().tryDeleteFile).toHaveBeenCalledWith("source", 2);

    expect(library().updateNewsletter).toHaveBeenCalledTimes(2);
    const n2EpubUpdate = vi.mocked(library().updateNewsletter).mock.calls[0];
    expect(n2EpubUpdate[0]).toBe(2);
    expect(n2EpubUpdate[1](newsletters[1])).toEqual({
      epubVersion: null,
      epubLastAccessedAt: null,
    });
    const n2SourceUpdate = vi.mocked(library().updateNewsletter).mock.calls[1];
    expect(n2SourceUpdate[0]).toBe(2);
    expect(n2SourceUpdate[1](newsletters[1])).toEqual({
      sourceLastAccessedAt: null,
    });

    expect(postMessage).toHaveBeenCalledTimes(1);
    expect(postMessage).toHaveBeenCalledWith(
      buildWorkerMessage("newsletters updated", {}),
    );
  });

  it("should delete epub & source files for read newsletters downloaded more than 3 days ago", async () => {
    vi.mocked(files().tryDeleteFile).mockResolvedValueOnce(true);
    vi.mocked(files().tryDeleteFile).mockResolvedValueOnce(true);

    const newsletters = [
      buildNewsletter(
        1,
        "2025-09-01 12:00:00.000000+00",
        false, // read = false, don't delete files
        false,
        "2025-09-01 12:00:00.000000+00",
        "2025-09-01 12:00:00.000000+00",
        "2025-09-01 12:00:00.000000+00",
      ),
      buildNewsletter(
        2,
        "2025-09-02 12:00:00.000000+00",
        true, // read = true, delete epub & source files
        false,
        "2025-09-02 12:00:01.000000+00",
        "2025-09-01 12:00:00.000000+00",
        "2025-09-01 12:00:00.000000+00",
      ),
    ];
    vi.mocked(library().getAllNewsletters).mockResolvedValue(newsletters);

    await downloadManager.setAuthToken("mock-token");
    await downloadManager.setLibraryInitialized();

    expect(files().tryDeleteFile).toHaveBeenCalledTimes(2);
    expect(files().tryDeleteFile).toHaveBeenCalledWith("epub", 2);
    expect(files().tryDeleteFile).toHaveBeenCalledWith("source", 2);

    expect(library().updateNewsletter).toHaveBeenCalledTimes(2);
    const n2EpubUpdate = vi.mocked(library().updateNewsletter).mock.calls[0];
    expect(n2EpubUpdate[0]).toBe(2);
    expect(n2EpubUpdate[1](newsletters[1])).toEqual({
      epubVersion: null,
      epubLastAccessedAt: null,
    });
    const n2SourceUpdate = vi.mocked(library().updateNewsletter).mock.calls[1];
    expect(n2SourceUpdate[0]).toBe(2);
    expect(n2SourceUpdate[1](newsletters[1])).toEqual({
      sourceLastAccessedAt: null,
    });

    expect(postMessage).toHaveBeenCalledTimes(1);
    expect(postMessage).toHaveBeenCalledWith(
      buildWorkerMessage("newsletters updated", {}),
    );
  });
});
