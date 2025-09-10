import { type ReactNode, useState, useEffect } from "react";
import useAuthToken from "./useAuthToken";
import AuthForm from "./AuthForm";
import AuthVerifier from "./AuthVerifier";
import { SyncWorker } from "./SyncWorker";
import { DownloadWorker } from "./DownloadWorker";
import { buildMainMessage } from "./WorkerTypes";

interface AuthWrapperProps {
  children: ReactNode;
}

function AuthWrapper({ children }: AuthWrapperProps) {
  const [authToken, setAuthToken] = useAuthToken();
  const [authVerified, setAuthVerified] = useState(false);

  useEffect(() => {
    SyncWorker.postMessage(buildMainMessage("auth token", { authToken }));
    DownloadWorker.postMessage(buildMainMessage("auth token", { authToken }));
  }, [authToken]);

  if (!authToken) {
    return <AuthForm setAuthToken={setAuthToken} />;
  } else if (!authVerified) {
    return (
      <AuthVerifier
        authToken={authToken}
        setAuthVerified={setAuthVerified}
        setAuthToken={setAuthToken}
      />
    );
  } else {
    return <>{children}</>;
  }
}

export default AuthWrapper;
