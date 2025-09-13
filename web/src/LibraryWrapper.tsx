import { type ReactNode, useState, useEffect } from "react";
import CenteredHalfAlert from "./CenteredHalfAlert";
import library from "./Library";
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
  }, [databaseInitialized]);

  if (error) {
    return <CenteredHalfAlert severity="error">{error}</CenteredHalfAlert>;
  } else if (!databaseInitialized) {
    return (
      <DelayedElement>
        <CenteredHalfAlert severity="info">
          Initializing database...
        </CenteredHalfAlert>
      </DelayedElement>
    );
  } else {
    return <>{children}</>;
  }
}

export default LibraryWrapper;
