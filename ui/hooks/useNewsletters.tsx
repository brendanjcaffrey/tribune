import {
  use,
  createContext,
  type PropsWithChildren,
  useRef,
  useCallback,
  useState,
} from "react";
import { useEffect } from "react";
import * as FileSystem from "expo-file-system";
import { Alert, ToastAndroid, Platform } from "react-native";
import { AuthState, useAuth } from "@/hooks/useAuth";
import { useStorage } from "@/hooks/useStorage";

export function parseTimestamp(ts: string): Date {
  const [date, timeZone] = ts.split(" ");
  let [time] = timeZone.split("+");
  if (time.includes(".")) {
    const [hms, frac] = time.split(".");
    time = `${hms}.${frac.substring(0, 3)}`;
  }
  return new Date(`${date}T${time}Z`);
}

export interface Newsletter {
  id: number;
  title: string;
  author: string;
  read: boolean;
  deleted: boolean;
  created_at: string;
  updated_at: string;
  downloadStatus?: "pending" | "downloading" | "downloaded";
  filePath?: string;
}

interface NewslettersContextValue {
  newsletters: Newsletter[];
  isLoading: boolean;
  syncInProgress: boolean;
  clear: () => void;
  sync: () => void;
}

const NewslettersContext = createContext<NewslettersContextValue>({
  newsletters: [],
  isLoading: false,
  syncInProgress: false,
  clear: () => {},
  sync: () => {},
});

interface NewsletterResponseMeta {
  before_timestamp?: string;
  before_id?: number;
  after_timestamp?: string;
  after_id?: number;
}

interface NewslettersResposne {
  meta: NewsletterResponseMeta;
  result: Newsletter[];
}

export function useNewsletters() {
  const value = use(NewslettersContext);
  if (!value) {
    throw new Error(
      "useNewsletters must be wrapped in a <NewslettersProvider />",
    );
  }
  return value;
}

export function NewslettersProvider({ children }: PropsWithChildren) {
  const { state: auth, isLoading: authLoading } = useAuth();
  const [[initialSyncDoneLoading, initialSyncDone], setInitialSyncDone] =
    useStorage<boolean>("initialSyncDone");
  const [[newslettersLoading, newsletters], setNewsletters] =
    useStorage<Newsletter[]>("newsletters");
  const [syncToggle, setSyncToggle] = useState(false);
  const [downloadToggle, setDownloadToggle] = useState(false);
  const isLoading = authLoading || newslettersLoading || initialSyncDoneLoading;
  const syncInProgressRef = useRef(false);
  const downloadingRef = useRef(false);
  const newslettersRef = useRef<Newsletter[]>(newsletters ?? []);

  useEffect(() => {
    newslettersRef.current = newsletters ?? [];
  }, [newsletters]);

  const clear = useCallback(() => {
    setNewsletters([]);
    setInitialSyncDone(false);
  }, [setNewsletters, setInitialSyncDone]);

  const updateNewsletter = useCallback(
    (id: number, partial: Partial<Newsletter>) => {
      const updated = newslettersRef.current.map((n) =>
        n.id === id ? { ...n, ...partial } : n,
      );
      newslettersRef.current = updated;
      setNewsletters(updated);
    },
    [setNewsletters],
  );

  const sync = useCallback(() => {
    if (syncInProgressRef.current) {
      return;
    }
    setSyncToggle((prev) => !prev);
  }, [setSyncToggle]);

  useEffect(() => {
    if (syncInProgressRef.current) {
      return;
    }
    if (isLoading) {
      return;
    }
    if (!auth) {
      return;
    }

    syncInProgressRef.current = true;
    let controller = new AbortController();
    if (!initialSyncDone) {
      performInitialSync(auth, controller.signal)
        .then((newsletters) => {
          if (!controller.signal.aborted && newsletters) {
            setNewsletters(newsletters);
            setInitialSyncDone(true);
          }
        })
        .catch((e) => {
          if (!controller.signal.aborted) {
            console.error("Error during initial sync", e);
            setNewsletters([]);
            setInitialSyncDone(false);
          }
        })
        .finally(() => {
          syncInProgressRef.current = false;
          setDownloadToggle((prev) => !prev);
        });
    } else {
      const newestNewsletter =
        newsletters && newsletters.length > 0 ? newsletters[0] : null;
      performUpdateSync(
        auth,
        newestNewsletter?.updated_at,
        newestNewsletter?.id,
        newsletters ?? [],
        controller.signal,
      )
        .then((newsletters) => {
          if (!controller.signal.aborted && newsletters) {
            setNewsletters(newsletters);
            setInitialSyncDone(true);
          }
        })
        .catch((e) => {
          if (!controller.signal.aborted) {
            console.error("Error during update sync", e);
            setNewsletters([]);
            setInitialSyncDone(false);
          }
        })
        .finally(() => {
          syncInProgressRef.current = false;
          setDownloadToggle((prev) => !prev);
        });
    }

    return () => {
      controller.abort();
    };
  }, [isLoading, auth, syncToggle, setNewsletters, setInitialSyncDone]);

  useEffect(() => {
    if (syncInProgressRef.current || downloadingRef.current) {
      return;
    }
    if (!auth) {
      return;
    }
    const pending = (newslettersRef.current || [])
      .filter((n) => !n.read && n.downloadStatus !== "downloaded")
      .sort((a, b) => {
        const at = parseTimestamp(a.updated_at);
        const bt = parseTimestamp(b.updated_at);
        if (at > bt) return -1;
        if (at < bt) return 1;
        return b.id - a.id;
      });
    if (pending.length === 0) {
      return;
    }

    downloadingRef.current = true;

    const downloadNext = async (index: number) => {
      if (index >= pending.length) {
        downloadingRef.current = false;
        return;
      }

      const item = pending[index];
      updateNewsletter(item.id, { downloadStatus: "downloading" });
      const dest = `${FileSystem.documentDirectory}${item.id}.epub`;
      let delay = 500;
      let success = false;
      for (let attempt = 0; attempt < 3; attempt++) {
        try {
          await FileSystem.downloadAsync(
            `${auth.host}/newsletters/${item.id}/epub`,
            dest,
            { headers: { Authorization: `Bearer ${auth.jwt}` } },
          );
          success = true;
          break;
        } catch (e) {
          console.error("Failed to download", e);
          Alert.alert("Download failed", `Failed to download ${item.title}`);
          await new Promise((r) => setTimeout(r, delay));
          delay *= 2;
        }
      }

      if (success) {
        updateNewsletter(item.id, {
          downloadStatus: "downloaded",
          filePath: dest,
        });
      } else {
        updateNewsletter(item.id, { downloadStatus: "pending" });
      }

      downloadNext(index + 1);
    };

    downloadNext(0);
  }, [auth, updateNewsletter, downloadToggle]);

  return (
    <NewslettersContext.Provider
      value={{
        newsletters: newsletters ?? [],
        isLoading,
        syncInProgress: syncInProgressRef.current,
        clear,
        sync,
      }}
    >
      {children}
    </NewslettersContext.Provider>
  );
}

async function performInitialSync(
  auth: AuthState,
  abortSignal: AbortSignal,
): Promise<Newsletter[] | null> {
  const all: Newsletter[] = [];
  let beforeTimestamp: string | undefined;
  let beforeId: number | undefined;
  const threeMonthsAgo = new Date();
  threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

  while (true) {
    const params = new URLSearchParams();
    if (beforeTimestamp && beforeId !== undefined) {
      params.append("before_timestamp", beforeTimestamp);
      params.append("before_id", beforeId.toString());
    }

    try {
      const url = `${auth.host}/newsletters?${params.toString()}`;
      const resp = await fetch(url, {
        headers: { Authorization: `Bearer ${auth.jwt}` },
        signal: abortSignal,
      });
      if (!resp.ok) {
        console.warn("Failed to fetch newsletters", resp.status);
        return null;
      }

      const data = (await resp.json()) as NewslettersResposne;
      if (
        (beforeTimestamp || beforeId !== undefined) &&
        (data.meta.before_timestamp !== beforeTimestamp ||
          data.meta.before_id !== beforeId)
      ) {
        console.error(
          `Pagination parameters not echoed back correctly ${beforeTimestamp} vs ${data.meta.before_timestamp}, ${beforeId} vs ${data.meta.before_id}`,
        );
        return null;
      }

      const validItems = data.result
        .filter(
          (n) => !n.deleted && parseTimestamp(n.updated_at) >= threeMonthsAgo,
        )
        .map((n) => ({ ...n, downloadStatus: "pending" as const }));
      all.push(...validItems);

      if (
        data.result.length < 100 ||
        parseTimestamp(
          data.result[data.result.length - 1]?.updated_at ??
            "1970-01-01 00:00:00+00",
        ) < threeMonthsAgo
      ) {
        break;
      }

      const last = data.result[data.result.length - 1];
      beforeTimestamp = last.updated_at;
      beforeId = last.id;
    } catch (e) {
      console.error("Error syncing newsletters", e);
      return null;
    }
  }

  return all;
}

async function performUpdateSync(
  auth: AuthState,
  afterTimestamp: string | undefined,
  afterId: number | undefined,
  current: Newsletter[],
  abortSignal: AbortSignal,
): Promise<Newsletter[] | null> {
  let beforeTimestamp: string | undefined;
  let beforeId: number | undefined;
  const threeMonthsAgo = new Date();
  threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);

  const params = new URLSearchParams();
  if (afterTimestamp && afterId !== undefined) {
    params.append("after_timestamp", afterTimestamp);
    params.append("after_id", afterId.toString());
  }

  try {
    const url = `${auth.host}/newsletters?${params.toString()}`;
    const resp = await fetch(url, {
      headers: { Authorization: `Bearer ${auth.jwt}` },
      signal: abortSignal,
    });
    if (!resp.ok) {
      console.warn("Failed to fetch newsletters", resp.status);
      return null;
    }

    const data = (await resp.json()) as NewslettersResposne;
    if (
      (beforeTimestamp || beforeId !== undefined) &&
      (data.meta.before_timestamp !== beforeTimestamp ||
        data.meta.before_id !== beforeId)
    ) {
      console.error(
        `Pagination parameters not echoed back correctly ${beforeTimestamp} vs ${data.meta.before_timestamp}, ${beforeId} vs ${data.meta.before_id}`,
      );
      return null;
    }

    // TODO if it's been a while since the last sync, we might need multiple calls of this
    const updatedIds = new Set(data.result.map((n) => n.id));
    let filteredCurrent = current.filter(
      (n) =>
        !updatedIds.has(n.id) && parseTimestamp(n.updated_at) >= threeMonthsAgo,
    );
    let filteredUpdated = data.result
      .filter((n) => !n.deleted)
      .map((n) => {
        const existing = current.find((c) => c.id === n.id);
        return {
          ...n,
          downloadStatus: existing?.downloadStatus ?? "pending",
          filePath: existing?.filePath,
        };
      });
    const next = [...filteredUpdated, ...filteredCurrent];
    const remainingIds = new Set(next.map((n) => n.id));
    await Promise.all(
      current
        .filter((n) => !remainingIds.has(n.id) && n.filePath)
        .map((n) =>
          FileSystem.deleteAsync(n.filePath!, { idempotent: true }).catch((e) =>
            console.warn("Failed to delete", e),
          ),
        ),
    );
    return next;
  } catch (e) {
    console.error("Error syncing newsletters", e);
    return null;
  }
}
