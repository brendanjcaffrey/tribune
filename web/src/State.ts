import { atom, createStore } from "jotai";
import { SortableNewsletter } from "./SortableNewsletter";

export const store = createStore();

export const searchAtom = atom("");
export const anyDownloadErrorsAtom = atom(false);
export const newsletterDoubleClickedCallbackAtom = atom({
  fn: (_: SortableNewsletter) => {}, // eslint-disable-line
});
