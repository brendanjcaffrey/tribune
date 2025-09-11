import { useCallback, useEffect, useRef, useState } from "react";
import { SyncWorker } from "./SyncWorker";
import { enqueueSnackbar } from "notistack";
import library, { type Newsletter } from "./Library";
import { AgGridReact } from "ag-grid-react";
import {
  ModuleRegistry,
  AllCommunityModule,
  type GridOptions,
  themeMaterial,
} from "ag-grid-community";
import { useAtomValue } from "jotai";
import { searchAtom } from "./State";

ModuleRegistry.registerModules([AllCommunityModule]);

type SortableNewsletter = Omit<Newsletter, "createdAt"> & {
  createdAt: Date;
  sortIndex: number;
};

const gridOptions: GridOptions = {
  autoSizeStrategy: {
    type: "fitCellContents",
  },
  suppressCellFocus: true,
  columnDefs: [
    { field: "id", hide: true },
    {
      field: "sortIndex",
      headerName: "Sort",
      filter: false,
      sort: "desc",
      hide: true,
    },
    { field: "title" },
    { field: "author" },
    { field: "createdAt", cellDataType: "dateTime" },
  ],
  defaultColDef: {
    filter: true,
  },
};

function NewsletterList() {
  const gridRef = useRef<AgGridReact>(null);
  const [newsletters, setNewsletters] = useState<SortableNewsletter[]>([]);
  const search = useAtomValue(searchAtom);

  const updateNewsletters = useCallback(async () => {
    const newsletters = await library().getAllNewsletters();
    setNewsletters(
      newsletters
        .filter((n) => !n.deleted)
        .map((n, i) => {
          return { ...n, createdAt: new Date(n.createdAt), sortIndex: i };
        }),
    );
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

  useEffect(() => {
    if (gridRef.current && gridRef.current.api) {
      gridRef.current.api.setGridOption("quickFilterText", search);
    }
  }, [search]);

  return (
    <div style={{ height: "98%", width: "100%" }}>
      <AgGridReact
        ref={gridRef}
        theme={themeMaterial}
        gridOptions={gridOptions}
        rowData={newsletters}
      />
    </div>
  );
}

export default NewsletterList;
