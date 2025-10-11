import { atom } from "jotai";

const DOWNLOAD_MODE_KEY = "downloadMode";
function GetPersistedDownloadMode(): boolean {
  const value = localStorage.getItem(DOWNLOAD_MODE_KEY);
  if (value === null) {
    return false;
  } else {
    return value === "true";
  }
}

export function PersistedDownloadMode(value: boolean) {
  localStorage.setItem(DOWNLOAD_MODE_KEY, value.toString());
}

export const downloadModeAtom = atom(GetPersistedDownloadMode());

const DOWNLOAD_PDFS_KEY = "downloadPDFs";
function GetPersistedDownloadPDFs(): boolean {
  const value = localStorage.getItem(DOWNLOAD_PDFS_KEY);
  if (value === null) {
    return false;
  } else {
    return value === "true";
  }
}

export function PersistDownloadPDFs(value: boolean) {
  localStorage.setItem(DOWNLOAD_PDFS_KEY, value.toString());
}

export const downloadPDFsAtom = atom(GetPersistedDownloadPDFs());
