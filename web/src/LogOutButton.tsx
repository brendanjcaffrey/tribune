import { useAtomValue } from "jotai";
import Button, { ButtonOwnProps } from "@mui/material/Button";
import LogoutIcon from "@mui/icons-material/Logout";
import { clearAuthFnAtom, clearSettingsFnAtom } from "./State";
import library from "./Library";
import downloadsStore from "./Library";
import { files } from "./Files";
import { WorkerInstance } from "./WorkerInstance";
import { buildMainMessage } from "./WorkerTypes";

interface LogOutButtonProps {
  size?: ButtonOwnProps["size"];
  sx?: ButtonOwnProps["sx"];
}

function LogOutButton({ size, sx }: LogOutButtonProps) {
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
    <Button
      color="primary"
      variant="text"
      size={size}
      sx={sx}
      startIcon={<LogoutIcon />}
      onClick={clearAllState}
    >
      Log Out
    </Button>
  );
}

export default LogOutButton;
