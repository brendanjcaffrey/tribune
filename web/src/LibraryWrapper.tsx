import { type ReactNode, useState, useEffect } from "react";
import CenteredHalfAlert from "./CenteredHalfAlert";
import library from "./Library";
import { SyncWorker } from "./SyncWorker";
import type { WorkerToMainMessage } from "./WorkerTypes";
import DelayedElement from "./DelayedElement";

interface LibraryWrapperProps {
  children: ReactNode;
}

function LibraryWrapper({ children }: LibraryWrapperProps) {
  const [error, setError] = useState("");
  const [databaseInitialized, setDatabaseInitialized] = useState(false);

  useEffect(() => {
    library().setInitializedListener(() => {
      setDatabaseInitialized(true);
    });
  }, []);

  useEffect(() => {
    if (!databaseInitialized) {
      return;
    }

    library().setErrorListener((error) => {
      setError(error);
    });

    const listener = SyncWorker.addMessageListener(
      (msg: WorkerToMainMessage, ev: MessageEvent<WorkerToMainMessage>) => {
        console.log(msg);
        console.log(ev);
      },
    );

    return () => {
      SyncWorker.removeMessageListener(listener);
    };
  }, [databaseInitialized]);

  if (error) {
    return <CenteredHalfAlert severity="error">{error}</CenteredHalfAlert>;
  } else if (!databaseInitialized) {
    return (
      <DelayedElement>
        <CenteredHalfAlert>Initializing database...</CenteredHalfAlert>
      </DelayedElement>
    );
  } else {
    return <>{children}</>;
  }
}

export default LibraryWrapper;
