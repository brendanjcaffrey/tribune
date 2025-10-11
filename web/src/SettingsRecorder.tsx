import { useAtom, useSetAtom } from "jotai";
import { clearSettingsFnAtom } from "./State";
import { useEffect } from "react";
import {
  downloadModeAtom,
  downloadPDFsAtom,
  PersistDownloadPDFs,
  PersistedDownloadMode,
} from "./Settings";
import { WorkerInstance } from "./WorkerInstance";
import { buildMainMessage } from "./WorkerTypes";

function SettingsRecorder() {
  const [downloadMode, setDownloadMode] = useAtom(downloadModeAtom);
  const [downloadPDFs, setDownloadPDFs] = useAtom(downloadPDFsAtom);
  const setClearSettingsFn = useSetAtom(clearSettingsFnAtom);

  useEffect(() => {
    setClearSettingsFn({
      fn: () => {
        setDownloadMode(false);
        setDownloadPDFs(false);
      },
    });
  }, [setDownloadMode, setDownloadPDFs, setClearSettingsFn]);

  useEffect(() => {
    PersistedDownloadMode(downloadMode);
    WorkerInstance.postMessage(
      buildMainMessage("set download mode", { enabled: downloadMode }),
    );
  }, [downloadMode]);

  useEffect(() => {
    PersistDownloadPDFs(downloadPDFs);
    WorkerInstance.postMessage(
      buildMainMessage("set download pdfs", { enabled: downloadPDFs }),
    );
  }, [downloadPDFs]);

  return null;
}

export default SettingsRecorder;
