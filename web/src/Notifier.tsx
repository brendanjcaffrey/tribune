import { useEffect } from "react";
import { WorkerInstance } from "./WorkerInstance";
import { enqueueSnackbar } from "notistack";

function Notifier() {
  useEffect(() => {
    const listener = WorkerInstance.addMessageListener(async (message) => {
      if (message.type == "info") {
        enqueueSnackbar(`${message.info}`, {
          variant: "info",
          autoHideDuration: 1500,
        });
      } else if (message.type == "error") {
        enqueueSnackbar(`worker error: ${message.error}`, {
          variant: "error",
        });
      }
    });
    return () => {
      WorkerInstance.removeMessageListener(listener);
    };
  }, []);

  return null;
}

export default Notifier;
