import { useEffect, useState } from "react";
import { useAtom, useAtomValue } from "jotai";
import { anyDownloadErrorsAtom, authVerifiedAtom, searchAtom } from "./State";
import DownloadsPanel from "./DownloadsPanel";
import SettingsPanel from "./SettingsPanel";
import ReadStatusToggle from "./ReadStatusToggle";
import { WorkerInstance } from "./WorkerInstance";
import { buildMainMessage } from "./WorkerTypes";
import { useColorScheme } from "./useColorScheme";

import Navbar from "react-bootstrap/Navbar";
import Button from "react-bootstrap/Button";
import Form from "react-bootstrap/Form";
import InputGroup from "react-bootstrap/InputGroup";
import OverlayTrigger from "react-bootstrap/OverlayTrigger";
import Tooltip from "react-bootstrap/Tooltip";

import {
  ArrowRepeat,
  BoxArrowUpRight,
  Download,
  Gear,
  Search,
  XLg,
} from "react-bootstrap-icons";
import { Newsletter } from "./Library";
import { isDevelopment } from "./Environment";
import { openSourceUrl, sourceUrl } from "./Util";

interface TopBarProps {
  newsletterShown: boolean;
  displayedNewsletter: Newsletter | null;
  closeNewsletter: () => void;
}

export default function TopBar({
  newsletterShown,
  displayedNewsletter,
  closeNewsletter,
}: TopBarProps) {
  const [search, setSearch] = useAtom(searchAtom);
  const anyDownloadErrors = useAtomValue(anyDownloadErrorsAtom);
  const [showDownloads, setShowDownloads] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [syncRunning, setSyncRunning] = useState(false);
  const authVerified = useAtomValue(authVerifiedAtom);
  const colorScheme = useColorScheme();

  // development gets its own navbar color so it can't be confused with production
  const navbarBg = isDevelopment
    ? "danger"
    : colorScheme === "dark"
      ? "dark"
      : "primary";

  // newsletters saved from a web page keep the page url as their source id, so the one
  // being read can be opened at its original location
  const displayedUrl = newsletterShown
    ? sourceUrl(displayedNewsletter?.sourceId)
    : null;

  const toggleShowDownloads = () => {
    setShowDownloads((prev) => !prev);
  };

  const toggleShowSettings = () => {
    setShowSettings((prev) => !prev);
  };

  const startSync = () => {
    WorkerInstance.postMessage(
      buildMainMessage("start sync", { background: false }),
    );
  };

  useEffect(() => {
    if (!authVerified) {
      setShowDownloads(false);
      setShowSettings(false);
    }
  }, [authVerified]);

  useEffect(() => {
    const listener = WorkerInstance.addMessageListener(async (message) => {
      if (message.type === "sync status") {
        setSyncRunning(message.running);
      }
    });
    return () => {
      WorkerInstance.removeMessageListener(listener);
    };
  }, []);

  useEffect(() => {
    if (authVerified) {
      const handleFocus = () => {
        WorkerInstance.postMessage(
          buildMainMessage("start sync", { background: true }),
        );
      };
      window.addEventListener("focus", handleFocus);
      return () => window.removeEventListener("focus", handleFocus);
    }
  }, [authVerified]);

  return (
    <>
      <Navbar bg={navbarBg} data-bs-theme="dark" className="px-3">
        <Navbar.Brand className="text-truncate me-0">
          {newsletterShown && displayedNewsletter
            ? displayedNewsletter.title
            : "Tribune"}
        </Navbar.Brand>
        {displayedUrl !== null && (
          <OverlayTrigger
            placement="bottom"
            overlay={<Tooltip>Open URL</Tooltip>}
          >
            <Button
              variant="link"
              className="text-white p-1 flex-shrink-0"
              onClick={() => openSourceUrl(displayedUrl)}
              aria-label="open url"
            >
              <BoxArrowUpRight size={18} />
            </Button>
          </OverlayTrigger>
        )}
        {isDevelopment && (
          <Navbar.Text className="text-white ms-2 flex-shrink-0">
            Development
          </Navbar.Text>
        )}
        <div className="flex-grow-1" />
        {authVerified && !newsletterShown && (
          <div className="d-flex align-items-center gap-2">
            <InputGroup
              size="sm"
              style={{ width: "auto" }}
              data-bs-theme={colorScheme}
            >
              <InputGroup.Text>
                <Search />
              </InputGroup.Text>
              <Form.Control
                placeholder="Search…"
                aria-label="search"
                value={search}
                onChange={(e) => setSearch(e.target.value)}
              />
            </InputGroup>
            <div className="d-none d-md-flex align-items-center gap-1">
              <Button
                variant="link"
                className="text-white p-1"
                onClick={startSync}
                aria-label="sync"
              >
                <ArrowRepeat size={22} className={syncRunning ? "spin" : ""} />
              </Button>
              <OverlayTrigger
                placement="bottom"
                overlay={<Tooltip>Download Status</Tooltip>}
              >
                <Button
                  variant="link"
                  className="text-white p-1 position-relative"
                  onClick={toggleShowDownloads}
                  aria-label="download status"
                >
                  <Download size={22} />
                  {anyDownloadErrors && (
                    <span className="position-absolute top-0 start-100 translate-middle p-1 bg-danger border border-light rounded-circle">
                      <span className="visually-hidden">download errors</span>
                    </span>
                  )}
                </Button>
              </OverlayTrigger>
              <Button
                variant="link"
                className="text-white p-1"
                onClick={toggleShowSettings}
                aria-label="settings"
              >
                <Gear size={22} />
              </Button>
            </div>
          </div>
        )}
        {authVerified && newsletterShown && displayedNewsletter && (
          <div className="d-flex align-items-center gap-1">
            <ReadStatusToggle
              newsletterId={displayedNewsletter.id}
              initiallyRead={displayedNewsletter.read}
            />
            <Button
              variant="link"
              className="text-white p-1"
              onClick={closeNewsletter}
              aria-label="close"
            >
              <XLg size={22} />
            </Button>
          </div>
        )}
      </Navbar>
      <DownloadsPanel
        showDownloads={showDownloads}
        toggleShowDownloads={toggleShowDownloads}
      />
      <SettingsPanel
        showSettings={showSettings}
        toggleShowSettings={toggleShowSettings}
      />
    </>
  );
}
