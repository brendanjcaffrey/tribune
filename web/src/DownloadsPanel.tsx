import { useState, useEffect, useCallback, JSX } from "react";
import downloadsStore, { Download } from "./DownloadsStore";
import { formatBytes, formatTimestamp } from "./Util";
import { FileDownloadStatusMessage } from "./WorkerTypes";
import { WorkerInstance } from "./WorkerInstance";

import Dialog from "@mui/material/Dialog";
import DialogTitle from "@mui/material/DialogTitle";
import DialogContent from "@mui/material/DialogContent";
import DialogContentText from "@mui/material/DialogContentText";
import Table from "@mui/material/Table";
import TableBody from "@mui/material/TableBody";
import TableRow from "@mui/material/TableRow";
import TableCell from "@mui/material/TableCell";
import Tooltip from "@mui/material/Tooltip";

function DownloadStatusToDisplay(download: Download): JSX.Element {
  switch (download.status) {
    case "in progress":
      return <span>in progress</span>;
    case "done":
      return <span>done</span>;
    case "error":
      return <span color="red">error</span>;
    case "canceled":
      return <span>canceled</span>;
  }
}

function SizeDisplay(download: Download): JSX.Element {
  if (download.totalBytes === 0 || download.totalBytes === undefined) {
    return <span>?</span>;
  }

  if (
    download.status === "in progress" &&
    download.receivedBytes !== undefined
  ) {
    return (
      <span>
        {formatBytes(download.receivedBytes)}/{formatBytes(download.totalBytes)}
      </span>
    );
  } else {
    return <span>{formatBytes(download.totalBytes)}</span>;
  }
}

interface DownloadsPanelProps {
  showDownloads: boolean;
  toggleShowDownloads: () => void;
}

function DownloadsPanel({
  showDownloads,
  toggleShowDownloads,
}: DownloadsPanelProps) {
  const [downloads, setDownloads] = useState<Download[]>([]);
  const handleFileDownloadStatusMessage = useCallback(
    async (m: FileDownloadStatusMessage) => {
      await downloadsStore().update(m);
      setDownloads(downloadsStore().getAll());
    },
    [],
  );

  useEffect(() => {
    const listener = WorkerInstance.addMessageListener((message) => {
      if (message.type === "file download status") {
        handleFileDownloadStatusMessage(message);
      }
    });
    return () => {
      WorkerInstance.removeMessageListener(listener);
    };
  }, [handleFileDownloadStatusMessage]);

  return (
    <Dialog open={showDownloads} onClose={toggleShowDownloads} maxWidth="xl">
      <DialogTitle>Downloads</DialogTitle>
      <DialogContent>
        {downloads.length === 0 && (
          <DialogContentText>No downloads yet</DialogContentText>
        )}
        <Table>
          <TableBody>
            {downloads.map((d) => (
              <TableRow key={`${d.id}-${d.fileType}`}>
                <TableCell>
                  <Tooltip title={`newsletter id: ${d.id}`}>
                    <span>{d.trackDesc}</span>
                  </Tooltip>
                </TableCell>
                <TableCell>
                  <Tooltip title={`newsletter id: ${d.id}`}>
                    <span>{d.fileType}</span>
                  </Tooltip>
                </TableCell>
                <TableCell>{DownloadStatusToDisplay(d)}</TableCell>
                <TableCell>{SizeDisplay(d)}</TableCell>
                <TableCell>{formatTimestamp(d.lastUpdate)}</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </Table>
      </DialogContent>
    </Dialog>
  );
}

export default DownloadsPanel;
