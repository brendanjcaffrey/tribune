import { useAtom, useSetAtom } from "jotai";
import { clearSettingsFnAtom } from "./State";
import { useEffect } from "react";
import { downloadModeAtom, PersistedDownloadMode } from "./Settings";
import { WorkerInstance } from "./WorkerInstance";
import { buildMainMessage } from "./WorkerTypes";

function SettingsRecorder() {
  const [downloadMode, setDownloadMode] = useAtom(downloadModeAtom);
  const setClearSettingsFn = useSetAtom(clearSettingsFnAtom);

  useEffect(() => {
    setClearSettingsFn({
      fn: () => {
        setDownloadMode(false);
      },
    });
  }, [setDownloadMode, setClearSettingsFn]);

  useEffect(() => {
    PersistedDownloadMode(downloadMode);
    WorkerInstance.postMessage(
      buildMainMessage("set download mode", { enabled: downloadMode }),
    );
  }, [downloadMode]);

  return null;
}

export default SettingsRecorder;
