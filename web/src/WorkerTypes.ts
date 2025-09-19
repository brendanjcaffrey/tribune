export type FileType = "source" | "epub";
export type MimeType = "application/epub+zip" | "application/pdf" | "text/html";
export type DownloadStatus = "in progress" | "done" | "error" | "canceled";

export interface ErrorMessage {
  type: "error";
  error: string;
}

export interface StartSyncMessage {
  type: "start sync";
}

export interface SetAuthTokenMessage {
  type: "set auth token";
  authToken: string;
}

export interface ClearAuthTokenMessage {
  type: "clear auth token";
}

export interface NewslettersUpdated {
  type: "newsletters updated";
}

export interface DownloadFileMessage {
  type: "download file";
  fileType: FileType;
  mime: MimeType;
  id: number;
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
  receivedBytes: number | undefined;
  totalBytes: number | undefined;
}

export interface MarkNewsletterAsReadMessage {
  type: "mark newsletter as read";
  id: number;
}

export interface MarkNewsletterAsUnreadMessage {
  type: "mark newsletter as unread";
  id: number;
}

export type MainToWorkerMessage =
  | ErrorMessage
  | SetAuthTokenMessage
  | ClearAuthTokenMessage
  | StartSyncMessage
  | DownloadFileMessage
  | MarkNewsletterAsReadMessage
  | MarkNewsletterAsUnreadMessage;

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
