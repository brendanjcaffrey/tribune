import { useAtomValue } from "jotai";
import Button from "react-bootstrap/Button";
import { clearAuthFnAtom, clearSettingsFnAtom } from "./State";
import library from "./Library";
import downloadsStore from "./Library";
import { files } from "./Files";
import { WorkerInstance } from "./WorkerInstance";
import { buildMainMessage } from "./WorkerTypes";

function LogOutButton() {
  const clearAuthFn = useAtomValue(clearAuthFnAtom);
  const clearSettingsFn = useAtomValue(clearSettingsFnAtom);

  async function clearAllState() {
    clearAuthFn.fn();
    clearSettingsFn.fn();
    library().clear();
    await files().clearAll();
    WorkerInstance.postMessage(buildMainMessage("clear auth token", {}));
    downloadsStore().clear();
  }

  return (
    <Button variant="danger" onClick={clearAllState}>
      Log Out
    </Button>
  );
}

export default LogOutButton;
