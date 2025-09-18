import { atom, createStore } from "jotai";
import { SortableNewsletter } from "./SortableNewsletter";
import { NewsletterContextMenuData } from "./NewsletterContextMenu";

export const store = createStore();

export const authVerifiedAtom = atom(false);
export const searchAtom = atom("");
export const anyDownloadErrorsAtom = atom(false);

export const newsletterDoubleClickedCallbackAtom = atom({
  fn: (_: SortableNewsletter) => {}, // eslint-disable-line
});

export const showNewsletterContextMenuCallbackAtom = atom({
  fn: (_: NewsletterContextMenuData) => {}, // eslint-disable-line
});

export const clearAuthFnAtom = atom({ fn: () => {} });
