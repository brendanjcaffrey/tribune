import { useState, useEffect, useCallback, JSX } from "react";
import downloadsStore, { Download } from "./DownloadsStore";
import { formatBytes, formatTimestamp } from "./Util";
import { FileDownloadStatusMessage } from "./WorkerTypes";
import { WorkerInstance } from "./WorkerInstance";

import Modal from "react-bootstrap/Modal";
import Table from "react-bootstrap/Table";
import OverlayTrigger from "react-bootstrap/OverlayTrigger";
import Tooltip from "react-bootstrap/Tooltip";

function DownloadStatusToDisplay(download: Download): JSX.Element {
  switch (download.status) {
    case "in progress":
      return <span>in progress</span>;
    case "done":
      return <span>done</span>;
    case "error":
      return <span className="text-danger">error</span>;
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
    <Modal show={showDownloads} onHide={toggleShowDownloads} size="lg" centered>
      <Modal.Header closeButton>
        <Modal.Title>Downloads</Modal.Title>
      </Modal.Header>
      <Modal.Body>
        {downloads.length === 0 && (
          <p className="text-muted">No downloads yet</p>
        )}
        {downloads.length > 0 && (
          <Table hover size="sm">
            <tbody>
              {downloads.map((d) => (
                <tr key={`${d.id}-${d.fileType}`}>
                  <td>
                    <OverlayTrigger
                      overlay={<Tooltip>newsletter id: {d.id}</Tooltip>}
                    >
                      <span>{d.trackDesc}</span>
                    </OverlayTrigger>
                  </td>
                  <td>
                    <OverlayTrigger
                      overlay={<Tooltip>newsletter id: {d.id}</Tooltip>}
                    >
                      <span>{d.fileType}</span>
                    </OverlayTrigger>
                  </td>
                  <td>{DownloadStatusToDisplay(d)}</td>
                  <td>{SizeDisplay(d)}</td>
                  <td>{formatTimestamp(d.lastUpdate)}</td>
                </tr>
              ))}
            </tbody>
          </Table>
        )}
      </Modal.Body>
    </Modal>
  );
}

export default DownloadsPanel;
