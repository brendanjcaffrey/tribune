import { useCallback, useEffect, useRef, useState } from "react";
import { useWindowSize } from "@react-hook/window-size";
import { useAtomValue, useSetAtom } from "jotai";
import { useTheme } from "@mui/material/styles";
import Book from "@mui/icons-material/Book";
import Source from "@mui/icons-material/Source";
import { enqueueSnackbar } from "notistack";
import { AgGridReact, CustomCellRendererProps } from "ag-grid-react";
import {
  ModuleRegistry,
  AllCommunityModule,
  type GridOptions,
  themeMaterial,
  type CellContextMenuEvent,
  CellClassParams,
} from "ag-grid-community";

import { WorkerInstance } from "./WorkerInstance";
import library, { Newsletter } from "./Library";
import {
  showNewsletterFileCallbackAtom,
  searchAtom,
  showNewsletterContextMenuCallbackAtom,
  store,
  inProgressDownloadsAtom,
} from "./State";
import { SortableNewsletter } from "./SortableNewsletter";
import { buildMainMessage, FileType } from "./WorkerTypes";
import { files } from "./Files";
import { compareNewslettersForDisplay } from "./compareNewsletters";
import { GetBodyHeight } from "./Height";
import {
  NewsletterContextMenu,
  NewsletterContextMenuData,
} from "./NewsletterContextMenu";
import CircularProgress from "@mui/material/CircularProgress";

ModuleRegistry.registerModules([AllCommunityModule]);

function fadedIfRead(params: CellClassParams) {
  if (params.data && !params.data.read) {
    return null;
  } else if (params.data && params.data.read) {
    return { color: "gray" };
  } else {
    return null;
  }
}

const gridOptions: GridOptions = {
  suppressCellFocus: true,
  columnDefs: [
    {
      field: "id",
      hide: true,
    },
    {
      field: "sortIndex",
      headerName: "Sort",
      filter: false,
      sort: "asc",
      hide: true,
    },
    {
      field: "title",
      cellStyle: fadedIfRead,
      flex: 4,
      cellRenderer: (params: CustomCellRendererProps<SortableNewsletter>) => {
        return (
          <>
            {params.value}
            {params.data?.epubLastAccessedAt && (
              <Book
                fontSize="small"
                sx={{
                  verticalAlign: "middle",
                  paddingLeft: "2px",
                  transform: "scale(0.75)",
                }}
              />
            )}
            {params.data?.sourceLastAccessedAt && (
              <Source
                fontSize="small"
                sx={{
                  verticalAlign: "middle",
                  paddingLeft: "2px",
                  transform: "scale(0.75)",
                }}
              />
            )}
            {params.data &&
              store.get(inProgressDownloadsAtom).has(params.data.id) && (
                <CircularProgress size={12} sx={{ marginLeft: "4px" }} />
              )}
          </>
        );
      },
    },
    {
      field: "author",
      cellStyle: fadedIfRead,
      flex: 4,
    },
    {
      field: "createdAt",
      cellDataType: "dateTime",
      cellStyle: fadedIfRead,
      flex: 2,
      headerName: "Published",
    },
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
  const setInProgressDownloads = useSetAtom(inProgressDownloadsAtom);
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
    // the grid won't update after a big download mode pull without this
    setTimeout(() => {
      gridRef.current?.api.refreshCells({ force: true });
    }, 1);
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
      } else if (message.type === "file download status") {
        if (message.status === "in progress") {
          setInProgressDownloads((prev) => {
            const newMap = new Map(prev);
            if (!newMap.has(message.id)) {
              newMap.set(message.id, new Set());
            }
            newMap.get(message.id)?.add(message.fileType);
            return newMap;
          });
        } else {
          setInProgressDownloads((prev) => {
            const newMap = new Map(prev);
            if (newMap.has(message.id)) {
              newMap.get(message.id)?.delete(message.fileType);
              if (newMap.get(message.id)?.size === 0) {
                newMap.delete(message.id);
              }
            }
            return newMap;
          });
        }
        const row = gridRef.current?.api.getRowNode(message.id.toString());
        if (row !== undefined) {
          gridRef.current?.api.refreshCells({
            force: true,
            rowNodes: [row],
            columns: ["title"],
          });
        }
      }
    });
    updateNewsletters();
    return () => {
      WorkerInstance.removeMessageListener(listener);
    };
  }, [updateNewsletters, setNewsletterData, setInProgressDownloads]);

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
          getRowId={(n) => n.data.id.toString()}
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
