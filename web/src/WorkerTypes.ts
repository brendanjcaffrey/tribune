export type FileType = "source" | "epub";
export type DownloadStatus = "in progress" | "done" | "error" | "canceled";

export interface InfoMessage {
  type: "info";
  info: string;
}

export interface ErrorMessage {
  type: "error";
  error: string;
}

export interface SuccessMessage {
  type: "success";
  success: string;
}

export interface SetAuthTokenMessage {
  type: "set auth token";
  authToken: string;
}

export interface ClearAuthTokenMessage {
  type: "clear auth token";
}

export interface StartSyncMessage {
  type: "start sync";
  background: boolean;
}

export interface SyncStatusMessage {
  type: "sync status";
  running: boolean;
}

export interface NewslettersUpdated {
  type: "newsletters updated";
}

export interface DownloadFileMessage {
  type: "download file";
  fileType: FileType;
  mime: string;
  id: number;
}

export interface SetDownloadModeEnabledMessage {
  type: "set download mode";
  enabled: boolean;
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

export interface MarkNewsletterAsDeletedMessage {
  type: "mark newsletter as deleted";
  id: number;
}

export interface UpdateNewsletterProgressMessage {
  type: "update newsletter progress";
  id: number;
  progress: string;
}

export type MainToWorkerMessage =
  | ErrorMessage
  | SetAuthTokenMessage
  | ClearAuthTokenMessage
  | StartSyncMessage
  | DownloadFileMessage
  | SetDownloadModeEnabledMessage
  | MarkNewsletterAsReadMessage
  | MarkNewsletterAsUnreadMessage
  | MarkNewsletterAsDeletedMessage
  | UpdateNewsletterProgressMessage;

export type WorkerToMainMessage =
  | ErrorMessage
  | InfoMessage
  | SuccessMessage
  | SyncStatusMessage
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
