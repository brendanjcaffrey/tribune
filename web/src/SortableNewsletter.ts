import { Newsletter } from "./Library";

export type SortableNewsletter = Omit<Newsletter, "createdAt"> & {
  createdAt: Date;
  sortIndex: number;
};
