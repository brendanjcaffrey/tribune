import { type ReactNode, useEffect } from "react";
import useAuthToken from "./useAuthToken";
import AuthForm from "./AuthForm";
import AuthVerifier from "./AuthVerifier";
import { WorkerInstance } from "./WorkerInstance";
import { buildMainMessage } from "./WorkerTypes";
import { authVerifiedAtom, clearAuthFnAtom } from "./State";
import { useAtom, useSetAtom } from "jotai";

interface AuthWrapperProps {
  children: ReactNode;
}

function AuthWrapper({ children }: AuthWrapperProps) {
  const [authToken, setAuthToken] = useAuthToken();
  const [authVerified, setAuthVerified] = useAtom(authVerifiedAtom);
  const setClearAuthFn = useSetAtom(clearAuthFnAtom);

  useEffect(() => {
    if (authToken) {
      WorkerInstance.postMessage(
        buildMainMessage("set auth token", { authToken }),
      );
    }
  }, [authToken]);

  useEffect(() => {
    setClearAuthFn({
      fn: () => {
        setAuthToken("");
        setAuthVerified(false);
      },
    });
  }, [authToken, setAuthToken, setAuthVerified, setClearAuthFn]);

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
