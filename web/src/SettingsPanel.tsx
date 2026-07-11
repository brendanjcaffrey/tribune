import { useState, useEffect, type ReactNode } from "react";
import { enqueueToast } from "./Toasts";
import { formatBytes } from "./Util";
import LogOutButton from "./LogOutButton";
import { useAtom } from "jotai";
import { downloadModeAtom, downloadPDFsAtom } from "./Settings";

import Modal from "react-bootstrap/Modal";
import Form from "react-bootstrap/Form";
import Button from "react-bootstrap/Button";
import OverlayTrigger from "react-bootstrap/OverlayTrigger";
import Tooltip from "react-bootstrap/Tooltip";
import Popover from "react-bootstrap/Popover";
import { QuestionCircle } from "react-bootstrap-icons";

interface HelpButtonProps {
  children: ReactNode;
}

function HelpButton({ children }: HelpButtonProps) {
  return (
    <OverlayTrigger
      trigger="click"
      rootClose
      placement="bottom"
      overlay={
        <Popover>
          <Popover.Body style={{ maxWidth: "300px" }}>{children}</Popover.Body>
        </Popover>
      }
    >
      <Button variant="link" className="p-0 text-secondary" aria-label="help">
        <QuestionCircle />
      </Button>
    </OverlayTrigger>
  );
}

interface SettingsPanelProps {
  showSettings: boolean;
  toggleShowSettings: () => void;
}

function SettingsPanel({
  showSettings,
  toggleShowSettings,
}: SettingsPanelProps) {
  const [persisted, setPersisted] = useState(false);
  const [downloadMode, setDownloadMode] = useAtom(downloadModeAtom);
  const [downloadPDFs, setDownloadPDFs] = useAtom(downloadPDFsAtom);

  const handlePersistStorageChange = (
    event: React.ChangeEvent<HTMLInputElement>,
  ) => {
    if (persisted || !event.target.checked) {
      return;
    }
    navigator.storage.persist().then((granted) => {
      if (granted) {
        setPersisted(true);
      } else {
        enqueueToast("Persistent storage was not granted.", {
          variant: "error",
        });
      }
    });
  };

  const handleDownloadModeChange = (
    event: React.ChangeEvent<HTMLInputElement>,
  ) => {
    if (!persisted) {
      return;
    }
    setDownloadMode(event.target.checked);
    if (!event.target.checked) {
      setDownloadPDFs(false);
    }
  };

  const handleDownloadPDFsChange = (
    event: React.ChangeEvent<HTMLInputElement>,
  ) => {
    if (!persisted || !downloadMode) {
      return;
    }
    setDownloadPDFs(event.target.checked);
  };

  const [usage, setUsage] = useState(0);
  const [quota, setQuota] = useState(1);
  const percentageUsed = ((usage / quota) * 100).toFixed(2);

  useEffect(() => {
    const fetchStorageInfo = async () => {
      if (navigator.storage && navigator.storage.estimate) {
        const { usage, quota } = await navigator.storage.estimate();
        setUsage(usage || 0);
        setQuota(quota || 1);
      }

      if (navigator.storage && (await navigator.storage.persisted())) {
        setPersisted(true);
      } else {
        setPersisted(false);
      }
    };

    fetchStorageInfo();
    const interval = setInterval(fetchStorageInfo, 5000);

    return () => clearInterval(interval);
  }, []);

  return (
    <Modal show={showSettings} onHide={toggleShowSettings} centered>
      <Modal.Header closeButton>
        <Modal.Title>Settings</Modal.Title>
      </Modal.Header>
      <Modal.Body>
        <div style={{ width: "300px" }}>
          <div className="d-flex justify-content-between align-items-center mb-2">
            <Form.Check
              type="switch"
              id="persist-storage"
              label="Persist Storage"
              checked={persisted}
              disabled={persisted}
              onChange={handlePersistStorageChange}
            />
            <HelpButton>
              Request that the browser allow this app to store data persistently
              and give it a larger quota. Firefox will prompt you to allow this,
              but Chrome may not allow this until you use the app more. Once
              granted, it is not possible to revoke this permission.
            </HelpButton>
          </div>
          <div className="d-flex justify-content-between align-items-center mb-2">
            <Form.Check
              type="switch"
              id="download-mode"
              label="Download Mode"
              checked={downloadMode}
              disabled={!persisted}
              onChange={handleDownloadModeChange}
            />
            <HelpButton>
              Download mode will aggressively download all ePub files at page
              load so you can read them all without having an internet
              connection. This mode is only available if storage persistence is
              enabled.
            </HelpButton>
          </div>
          <div className="d-flex justify-content-between align-items-center mb-2">
            <Form.Check
              type="switch"
              id="download-pdfs"
              label="Download PDF Sources"
              checked={downloadPDFs}
              disabled={!downloadMode}
              onChange={handleDownloadPDFsChange}
            />
            <HelpButton>
              Download mode only downloads ePub files by default. With this
              option on, it will also download any PDF source files.
            </HelpButton>
          </div>
          <OverlayTrigger
            overlay={
              <Tooltip>
                {formatBytes(usage)} / {formatBytes(quota)}
              </Tooltip>
            }
          >
            <p className="mb-2">Storage Used: {percentageUsed}%</p>
          </OverlayTrigger>
          <div>
            <LogOutButton />
          </div>
        </div>
      </Modal.Body>
    </Modal>
  );
}

export default SettingsPanel;
