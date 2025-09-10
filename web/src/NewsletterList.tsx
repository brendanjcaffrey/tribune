import { useCallback, useEffect, useState } from "react";
import { SyncWorker } from "./SyncWorker";
import { enqueueSnackbar } from "notistack";
import library, { type Newsletter } from "./Library";
import { AgGridReact } from "ag-grid-react";
import {
  ModuleRegistry,
  AllCommunityModule,
  type ColDef,
} from "ag-grid-community";

ModuleRegistry.registerModules([AllCommunityModule]);

const colDefs: ColDef[] = [
  { field: "id", hide: true },
  { field: "title" },
  { field: "author" },
  { field: "createdAt", type: "dateTime" },
];

function NewsletterList() {
  const [newsletters, setNewsletters] = useState<Newsletter[]>([]);

  const updateNewsletters = useCallback(async () => {
    const newsletters = await library().getAllNewsletters();
    setNewsletters(newsletters.filter((n) => !n.deleted));
  }, [setNewsletters]);

  useEffect(() => {
    const listener = SyncWorker.addMessageListener((message) => {
      if (message.type == "error") {
        enqueueSnackbar(`sync worker error: ${message.error}`, {
          variant: "error",
        });
      } else if (message.type == "newsletters updated") {
        updateNewsletters();
      }
    });
    updateNewsletters();
    return () => {
      SyncWorker.removeMessageListener(listener);
    };
  }, [updateNewsletters]);

  return (
    <div style={{ height: "100%", width: "100%" }}>
      <AgGridReact rowData={newsletters} columnDefs={colDefs} />
    </div>
  );
}

export default NewsletterList;
