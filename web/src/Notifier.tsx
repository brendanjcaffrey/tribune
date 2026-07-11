import { useEffect } from "react";
import { WorkerInstance } from "./WorkerInstance";
import { enqueueToast } from "./Toasts";

function Notifier() {
  useEffect(() => {
    const listener = WorkerInstance.addMessageListener(async (message) => {
      if (message.type == "info") {
        enqueueToast(`${message.info}`, {
          variant: "info",
          autoHideDuration: 1500,
        });
      } else if (message.type == "error") {
        enqueueToast(`worker error: ${message.error}`, {
          variant: "error",
        });
      } else if (message.type == "success") {
        enqueueToast(message.success, {
          variant: "success",
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
