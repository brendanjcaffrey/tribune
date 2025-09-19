import { useAtomValue } from "jotai";
import { Button, ButtonOwnProps } from "@mui/material";
import { Logout } from "@mui/icons-material";
import { clearAuthFnAtom } from "./State";
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

  async function clearAllState() {
    clearAuthFn.fn();
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
      startIcon={<Logout />}
      onClick={clearAllState}
    >
      Log Out
    </Button>
  );
}

export default LogOutButton;
