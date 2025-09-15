import { useCallback, useEffect, useRef, useState } from "react";
import { SyncWorker } from "./SyncWorker";
import { enqueueSnackbar } from "notistack";
import library from "./Library";
import { AgGridReact } from "ag-grid-react";
import {
  ModuleRegistry,
  AllCommunityModule,
  type GridOptions,
  themeMaterial,
} from "ag-grid-community";
import { useAtomValue, useSetAtom } from "jotai";
import {
  newsletterDoubleClickedCallbackAtom,
  searchAtom,
  store,
} from "./State";
import { SortableNewsletter } from "./SortableNewsletter";
import { DownloadWorker } from "./DownloadWorker";
import { buildMainMessage } from "./WorkerTypes";
import { files } from "./Files";
import { useTheme } from "@mui/material";
import { compareNewslettersForDisplay } from "./compareNewsletters";
import { useWindowSize } from "@react-hook/window-size";
import { GetBodyHeight } from "./Height";

ModuleRegistry.registerModules([AllCommunityModule]);

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
  onRowDoubleClicked: (event) => {
    store
      .get(newsletterDoubleClickedCallbackAtom)
      .fn(event.data as SortableNewsletter);
  },
};

function NewsletterList(params: { setEpubUrl: (url: ArrayBuffer) => void }) {
  const gridRef = useRef<AgGridReact>(null);
  const pendingDownload = useRef<number | null>(null);
  const [newsletters, setNewsletters] = useState<SortableNewsletter[]>([]);
  const search = useAtomValue(searchAtom);
  const setNewsletterDoubleClickedCallback = useSetAtom(
    newsletterDoubleClickedCallbackAtom,
  );
  const [windowWidth, windowHeight] = useWindowSize();

  const muiTheme = useTheme();
  const agTheme = themeMaterial.withParams({
    backgroundColor: muiTheme.palette.background.default,
    foregroundColor: muiTheme.palette.text.primary,
    headerTextColor: muiTheme.palette.text.primary,
    headerBackgroundColor: muiTheme.palette.background.default,
    oddRowBackgroundColor: muiTheme.palette.action.selected,
    headerColumnResizeHandleColor: muiTheme.palette.info.main,
  });

  useEffect(() => {
    setNewsletterDoubleClickedCallback({
      fn: (n: SortableNewsletter) => {
        pendingDownload.current = n.id;
        DownloadWorker.postMessage(
          buildMainMessage("download file", {
            id: n.id,
            fileType: "epub",
            mime: "application/epub+zip",
          }),
        );
      },
    });
  }, [setNewsletterDoubleClickedCallback]);

  const updateNewsletters = useCallback(async () => {
    const newsletters = await library().getAllNewsletters();
    setNewsletters(
      newsletters
        .filter((n) => !n.deleted)
        .sort(compareNewslettersForDisplay)
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
    const listener = DownloadWorker.addMessageListener((message) => {
      if (message.type == "error") {
        enqueueSnackbar(`download worker error: ${message.error}`, {
          variant: "error",
        });
      } else if (message.type == "file fetched") {
        if (
          message.fileType === "epub" &&
          message.id === pendingDownload.current
        ) {
          files()
            .tryReadFile("epub", message.id)
            .then((file) => {
              if (file !== null) {
                file.arrayBuffer().then((buf) => {
                  params.setEpubUrl(buf);
                });
              }
            });
        }
      }
    });
    return () => {
      DownloadWorker.removeMessageListener(listener);
    };
  }, [params]);

  useEffect(() => {
    if (gridRef.current && gridRef.current.api) {
      gridRef.current.api.setGridOption("quickFilterText", search);
    }
  }, [search]);

  return (
    <div
      style={{
        height: `${GetBodyHeight(windowHeight)}px`,
        width: `${windowWidth}px`,
      }}
    >
      <AgGridReact
        ref={gridRef}
        theme={agTheme}
        gridOptions={gridOptions}
        rowData={newsletters}
      />
    </div>
  );
}

export default NewsletterList;
