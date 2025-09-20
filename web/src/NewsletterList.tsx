import { useCallback, useEffect, useRef, useState } from "react";
import { WorkerInstance } from "./WorkerInstance";
import library, { Newsletter } from "./Library";
import { AgGridReact } from "ag-grid-react";
import {
  ModuleRegistry,
  AllCommunityModule,
  type GridOptions,
  themeMaterial,
  type CellContextMenuEvent,
  CellClassParams,
} from "ag-grid-community";
import { useAtomValue, useSetAtom } from "jotai";
import {
  showNewsletterFileCallbackAtom,
  searchAtom,
  showNewsletterContextMenuCallbackAtom,
  store,
} from "./State";
import { SortableNewsletter } from "./SortableNewsletter";
import { buildMainMessage, FileType } from "./WorkerTypes";
import { files } from "./Files";
import { useTheme } from "@mui/material";
import { compareNewslettersForDisplay } from "./compareNewsletters";
import { useWindowSize } from "@react-hook/window-size";
import { GetBodyHeight } from "./Height";
import {
  NewsletterContextMenu,
  NewsletterContextMenuData,
} from "./NewsletterContextMenu";
import { enqueueSnackbar } from "notistack";

ModuleRegistry.registerModules([AllCommunityModule]);

function fadeRead(params: CellClassParams) {
  if (params.data && !params.data.read) {
    return null;
  } else if (params.data && params.data.read) {
    return { color: "gray" };
  } else {
    return null;
  }
}

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
      sort: "asc",
      hide: true,
    },
    {
      field: "title",
      cellStyle: fadeRead,
    },
    { field: "author", cellStyle: fadeRead },
    { field: "createdAt", cellDataType: "dateTime", cellStyle: fadeRead },
  ],
  defaultColDef: {
    filter: true,
    onCellContextMenu: (event: CellContextMenuEvent) => {
      // calling event.preventDefault() here doesn't work, have to do it in a click listener on the table wrapper element
      if (event.event === null) {
        return;
      }
      const mouseEvent = event.event as MouseEvent;
      const data: NewsletterContextMenuData = {
        newsletter: event.data as SortableNewsletter,
        mouseX: mouseEvent.clientX + 2,
        mouseY: mouseEvent.clientY - 6,
      };
      store.get(showNewsletterContextMenuCallbackAtom).fn(data);
    },
  },
  onRowClicked: (event) => {
    store
      .get(showNewsletterFileCallbackAtom)
      .fn(event.data as SortableNewsletter, "epub");
  },
};

interface NewsletterListProps {
  setNewsletterData: (newsletter: Newsletter, contents: ArrayBuffer) => void;
}

interface PendingDownload {
  id: number;
  fileType: FileType;
}

function NewsletterList({ setNewsletterData }: NewsletterListProps) {
  const gridRef = useRef<AgGridReact>(null);
  const pendingDownload = useRef<PendingDownload | null>(null);
  const [newsletters, setNewsletters] = useState<SortableNewsletter[]>([]);
  const [windowWidth, windowHeight] = useWindowSize();
  const [contextMenuData, setContextMenuData] =
    useState<NewsletterContextMenuData | null>(null);

  const search = useAtomValue(searchAtom);
  const setShowNewsletterFileCallback = useSetAtom(
    showNewsletterFileCallbackAtom,
  );
  const setShowNewsletterContextMenuCallback = useSetAtom(
    showNewsletterContextMenuCallbackAtom,
  );

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
    setShowNewsletterFileCallback({
      fn: (newsletter: SortableNewsletter, fileType: FileType) => {
        pendingDownload.current = { id: newsletter.id, fileType: fileType };
        WorkerInstance.postMessage(
          buildMainMessage("download file", {
            id: newsletter.id,
            fileType: fileType,
            mime:
              fileType == "epub"
                ? "application/epub+zip"
                : newsletter.sourceMimeType,
          }),
        );
      },
    });
  }, [setShowNewsletterFileCallback]);

  useEffect(() => {
    setShowNewsletterContextMenuCallback({
      fn: (d: NewsletterContextMenuData) => {
        setContextMenuData(d);
      },
    });
  }, [setShowNewsletterContextMenuCallback, setContextMenuData]);

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
    const listener = WorkerInstance.addMessageListener(async (message) => {
      if (message.type == "newsletters updated") {
        updateNewsletters();
      } else if (message.type == "file fetched") {
        if (
          message.fileType === pendingDownload.current?.fileType &&
          message.id === pendingDownload.current?.id
        ) {
          if (message.fileType === "epub") {
            const file = await files().tryReadFile(
              message.fileType,
              message.id,
            );
            const newsletter = await library().getNewsletter(message.id);
            if (file !== null && newsletter !== undefined) {
              const contents = await file.arrayBuffer();
              setNewsletterData(newsletter, contents);
            }
          } else {
            const url = await files().tryGetFileURL(
              message.fileType,
              message.id,
            );
            if (url !== null) {
              const handle = window.open(url, "_blank");
              if (handle === null) {
                enqueueSnackbar(
                  "Failed to open source, check popup blocker settings",
                  { variant: "error" },
                );
                URL.revokeObjectURL(url);
              } else {
                handle.addEventListener("unload", () => {
                  URL.revokeObjectURL(url);
                });
              }
            }
          }
        }
      }
    });
    updateNewsletters();
    return () => {
      WorkerInstance.removeMessageListener(listener);
    };
  }, [updateNewsletters, setNewsletterData]);

  useEffect(() => {
    if (gridRef.current && gridRef.current.api) {
      gridRef.current.api.setGridOption("quickFilterText", search);
    }
  }, [search]);

  return (
    <>
      <div
        style={{
          height: `${GetBodyHeight(windowHeight)}px`,
          width: `${windowWidth}px`,
        }}
        onContextMenu={(e) => {
          // this doesn't work in the ag grid handlers, so we have to do it here
          e.preventDefault();
        }}
      >
        <AgGridReact
          ref={gridRef}
          theme={agTheme}
          gridOptions={gridOptions}
          rowData={newsletters}
        />
      </div>
      <NewsletterContextMenu
        data={contextMenuData}
        handleClose={() => setContextMenuData(null)}
      />
    </>
  );
}

export default NewsletterList;
