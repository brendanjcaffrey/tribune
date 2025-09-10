export type FileType = "source" | "epub";
export type DownloadStatus = "in progress" | "done" | "error" | "canceled";

export interface ErrorMessage {
  type: "error";
  error: string;
}

export interface StartSyncMessage {
  type: "start sync";
}

export interface AuthTokenMessage {
  type: "auth token";
  authToken: string | null;
}

export interface NewslettersUpdated {
  type: "newsletters updated";
}

export interface FileFetchedMessage {
  type: "file fetched";
  fileType: FileType;
  id: number;
}

export interface FileDownloadStatusMessage {
  type: "file download status";
  id: number;
  fileType: FileType;
  status: DownloadStatus;
  receivedBytes: number;
  totalBytes: number;
}

export type MainToWorkerMessage =
  | ErrorMessage
  | AuthTokenMessage
  | StartSyncMessage;

export type WorkerToMainMessage =
  | ErrorMessage
  | NewslettersUpdated
  | FileFetchedMessage
  | FileDownloadStatusMessage;

export function buildMainMessage<T extends MainToWorkerMessage["type"]>(
  type: T,
  payload: Omit<Extract<MainToWorkerMessage, { type: T }>, "type">,
): Extract<MainToWorkerMessage, { type: T }> {
  return { type, ...payload } as Extract<MainToWorkerMessage, { type: T }>;
}

export function buildWorkerMessage<T extends WorkerToMainMessage["type"]>(
  type: T,
  payload: Omit<Extract<WorkerToMainMessage, { type: T }>, "type">,
): Extract<WorkerToMainMessage, { type: T }> {
  return { type, ...payload } as Extract<WorkerToMainMessage, { type: T }>;
}
