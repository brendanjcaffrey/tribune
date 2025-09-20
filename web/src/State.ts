import { atom, createStore } from "jotai";
import { SortableNewsletter } from "./SortableNewsletter";
import { NewsletterContextMenuData } from "./NewsletterContextMenu";
import { FileType } from "./WorkerTypes";

export const store = createStore();

export const authVerifiedAtom = atom(false);
export const searchAtom = atom("");
export const anyDownloadErrorsAtom = atom(false);

export const showNewsletterFileCallbackAtom = atom({
  fn: (_: SortableNewsletter, __: FileType) => {}, // eslint-disable-line
});

export const showNewsletterContextMenuCallbackAtom = atom({
  fn: (_: NewsletterContextMenuData) => {}, // eslint-disable-line
});

export const clearAuthFnAtom = atom({ fn: () => {} });
