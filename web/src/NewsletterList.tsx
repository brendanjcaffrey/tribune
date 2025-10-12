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
} from "ag-grid-community";

import { WorkerInstance } from "./WorkerInstance";
import library, { Newsletter } from "./Library";
import {
  showNewsletterFileCallbackAtom,
  searchAtom,
  showNewsletterContextMenuCallbackAtom,
  store,
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
      cellClassRules: {
        "is-read": (p) => !!p.data?.read,
      },
      flex: 4,
      valueGetter: (p) => ({
        title: p.data.title,
        hasEpub: p.data.epubLastAccessedAt !== null,
        hasSource: p.data.sourceLastAccessedAt !== null,
        isDownloading: p.data.downloadInProgress,
      }),
      equals: (a, b) =>
        a?.title === b?.title &&
        a?.hasEpub === b?.hasEpub &&
        a?.hasSource === b?.hasSource &&
        a?.isDownloading === b?.isDownloading,
      cellRenderer: (params: CustomCellRendererProps<SortableNewsletter>) => {
        return (
          <>
            {params.value.title}
            {params.value.hasEpub && (
              <Book
                fontSize="small"
                sx={{
                  verticalAlign: "middle",
                  paddingLeft: "2px",
                  transform: "scale(0.75)",
                }}
              />
            )}
            {params.value.hasSource && (
              <Source
                fontSize="small"
                sx={{
                  verticalAlign: "middle",
                  paddingLeft: "2px",
                  transform: "scale(0.75)",
                }}
              />
            )}
            {params.value.isDownloading && (
              <CircularProgress size={12} sx={{ marginLeft: "4px" }} />
            )}
          </>
        );
      },
    },
    {
      field: "author",
      cellClassRules: {
        "is-read": (p) => !!p.data?.read,
      },
      flex: 4,
    },
    {
      field: "createdAt",
      cellDataType: "dateTime",
      cellClassRules: {
        "is-read": (p) => !!p.data?.read,
      },
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

function NewsletterList({
  setNewsletterData: setDisplayedNewsletterData,
}: NewsletterListProps) {
  const gridRef = useRef<AgGridReact>(null);
  const pendingDownload = useRef<PendingDownload | null>(null);
  const [newsletters, setNewsletters] = useState<SortableNewsletter[]>([]);
  const [windowWidth, windowHeight] = useWindowSize();
  const inProgressDownloads = useRef<Map<number, Set<FileType>>>(new Map());
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

  const updateNewsletterDownloadStatus = useCallback(
    (id: number) => {
      setNewsletters((newsletters) => {
        const idx = newsletters.findIndex((n) => n.id === id);
        if (idx >= 0) {
          const updated = [...newsletters];
          updated[idx] = {
            ...updated[idx],
            downloadInProgress:
              inProgressDownloads.current.has(id) ||
              pendingDownload.current?.id === id,
          };
          return updated;
        } else {
          return newsletters;
        }
      });
    },
    [setNewsletters],
  );

  useEffect(() => {
    setShowNewsletterFileCallback({
      fn: (newsletter: SortableNewsletter, fileType: FileType) => {
        pendingDownload.current = { id: newsletter.id, fileType: fileType };
        updateNewsletterDownloadStatus(newsletter.id);
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
  }, [setShowNewsletterFileCallback, updateNewsletterDownloadStatus]);

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
          return {
            ...n,
            createdAt: new Date(n.createdAt),
            sortIndex: i,
            downloadInProgress: inProgressDownloads.current.has(n.id),
          };
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
              setDisplayedNewsletterData(newsletter, contents);
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
        const downloads = inProgressDownloads.current;
        if (message.status === "in progress") {
          if (!downloads.has(message.id)) {
            downloads.set(message.id, new Set());
          }
          downloads.get(message.id)?.add(message.fileType);
        } else {
          if (
            message.status === "error" ||
            (message.status === "canceled" &&
              pendingDownload.current?.id === message.id &&
              pendingDownload.current?.fileType === message.fileType)
          ) {
            pendingDownload.current = null;
          }
          if (downloads.has(message.id)) {
            downloads.get(message.id)?.delete(message.fileType);
            if (downloads.get(message.id)?.size === 0) {
              downloads.delete(message.id);
            }
          }
          updateNewsletterDownloadStatus(message.id);
        }
      }
    });
    updateNewsletters();
    return () => {
      WorkerInstance.removeMessageListener(listener);
    };
  }, [
    updateNewsletters,
    setDisplayedNewsletterData,
    updateNewsletterDownloadStatus,
  ]);

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
