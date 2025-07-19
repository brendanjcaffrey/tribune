import { use, createContext, type PropsWithChildren } from "react";
import { useEffect } from "react";
import { useAuth } from "@/hooks/useAuth";
import { useStorageState } from "@/hooks/useStorageState";

export interface Newsletter {
  id: number;
  title: string;
  author: string;
  filename: string;
  read: boolean;
  deleted: boolean;
  created_at: string;
  updated_at: string;
}

interface NewslettersContextValue {
  newsletters: Newsletter[];
  isLoading: boolean;
}

const NewslettersContext = createContext<NewslettersContextValue>({
  newsletters: [],
  isLoading: false,
});

export function useNewsletters() {
  const value = use(NewslettersContext);
  if (!value) {
    throw new Error("useNewsletters must be wrapped in a <NewslettersProvider />");
  }
  return value;
}

export function NewslettersProvider({ children }: PropsWithChildren) {
  const { state: authState } = useAuth();
  const [[loading, newsletters], setNewsletters] =
    useStorageState<Newsletter[]>("newsletters");

  useEffect(() => {
    if (!authState) {
      setNewsletters([]);
      return;
    }
    const { host, jwt } = authState;

    let cancelled = false;

    async function sync() {
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
        const url = `${host}/newsletters?${params.toString()}`;
        try {
          const resp = await fetch(url, {
            headers: { Authorization: `Bearer ${jwt}` },
          });
          if (!resp.ok) {
            console.warn("Failed to fetch newsletters", resp.status);
            break;
          }
          const data = (await resp.json()) as {
            meta: any;
            result: Newsletter[];
          };
          if (
            (beforeTimestamp || beforeId !== undefined) &&
            (data.meta.before_timestamp !== beforeTimestamp ||
              data.meta.before_id !== beforeId)
          ) {
            console.warn("Pagination parameters not echoed back correctly");
          }
          const validItems = data.result.filter(
            (n) => new Date(n.updated_at) >= threeMonthsAgo,
          );
          all.push(...validItems);
          if (
            data.result.length < 50 ||
            new Date(data.result[data.result.length - 1]?.updated_at ?? 0) <
              threeMonthsAgo
          ) {
            break;
          }
          const last = data.result[data.result.length - 1];
          beforeTimestamp = last.updated_at;
          beforeId = last.id;
        } catch (e) {
          console.error("Error syncing newsletters", e);
          break;
        }
      }

      if (!cancelled) {
        setNewsletters(all);
      }
    }

    sync();

    return () => {
      cancelled = true;
    };
  }, [authState, setNewsletters]);

  return (
    <NewslettersContext.Provider value={{ newsletters: newsletters ?? [], isLoading: loading }}>
      {children}
    </NewslettersContext.Provider>
  );
}
