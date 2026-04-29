import { isObject } from "lodash";
import { type ReactNode, useEffect } from "react";
import { useSetAtom } from "jotai";
import axios, { isAxiosError } from "axios";

import useAuthToken from "./useAuthToken";
import AuthForm from "./AuthForm";
import { WorkerInstance } from "./WorkerInstance";
import { buildMainMessage } from "./WorkerTypes";
import { authVerifiedAtom, clearAuthFnAtom } from "./State";

interface AuthWrapperProps {
  children: ReactNode;
}

// auth flow:
// - if there's no cached token, render the login form
// - otherwise treat the user as authenticated immediately so they can read
//   what's already cached (works with VPN down or server unreachable)
// - in the background, attempt to renew the token, only an explicit 401/403
//   from the server logs the user ou t
function AuthWrapper({ children }: AuthWrapperProps) {
  const [authToken, setAuthToken] = useAuthToken();
  const setAuthVerified = useSetAtom(authVerifiedAtom);
  const setClearAuthFn = useSetAtom(clearAuthFnAtom);

  useEffect(() => {
    if (authToken) {
      WorkerInstance.postMessage(
        buildMainMessage("set auth token", { authToken }),
      );
      setAuthVerified(true);
    } else {
      setAuthVerified(false);
    }
  }, [authToken, setAuthVerified]);

  useEffect(() => {
    const controller = new AbortController();
    (async () => {
      try {
        const { data } = await axios.put("/auth", undefined, {
          headers: { Authorization: `Bearer ${authToken}` },
          signal: controller.signal,
        });
        if (controller.signal.aborted) return;
        if (
          isObject(data) &&
          "jwt" in data &&
          typeof data["jwt"] === "string"
        ) {
          setAuthToken(data.jwt);
        }
      } catch (error) {
        if (controller.signal.aborted) return;
        if (
          isAxiosError(error) &&
          (error.response?.status === 401 || error.response?.status === 403)
        ) {
          setAuthToken("");
          return;
        }
        // network or server hiccup, leave the user signed in
        console.error("auth renewal deferred:", error);
      }
    })();

    return () => {
      controller.abort();
    };
  }, [authToken, setAuthToken]);

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
  }
  return <>{children}</>;
}

export default AuthWrapper;
