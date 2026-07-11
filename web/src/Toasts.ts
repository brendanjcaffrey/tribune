import { atom } from "jotai";
import { store } from "./State";

// small toast queue that replaces notistack. callers push messages from
// anywhere (including outside react) via enqueueToast, and Toaster renders them.

export type ToastVariant = "info" | "error" | "success";

export interface ToastData {
  id: number;
  message: string;
  variant: ToastVariant;
  autoHideDuration: number;
}

export const toastsAtom = atom<ToastData[]>([]);

const MAX_TOASTS = 3;
const DEFAULT_AUTO_HIDE = 4000;

let nextId = 0;

interface EnqueueOptions {
  variant?: ToastVariant;
  autoHideDuration?: number;
}

export function enqueueToast(message: string, options: EnqueueOptions = {}) {
  const toast: ToastData = {
    id: nextId++,
    message,
    variant: options.variant ?? "info",
    autoHideDuration: options.autoHideDuration ?? DEFAULT_AUTO_HIDE,
  };
  store.set(toastsAtom, (prev) => [...prev, toast].slice(-MAX_TOASTS));
}

export function dismissToast(id: number) {
  store.set(toastsAtom, (prev) => prev.filter((t) => t.id !== id));
}
