import { isObject } from "lodash";
import { useState, useEffect, useCallback, useRef } from "react";
import axios, { isAxiosError } from "axios";
import DelayedElement from "./DelayedElement";
import CenteredHalfAlert from "./CenteredHalfAlert";
import LogOutButton from "./LogOutButton";
import Button from "@mui/material/Button";

interface AuthVerifierProps {
  authToken: string;
  setAuthToken: (authToken: string) => void;
  setAuthVerified: (authChecked: boolean) => void;
}

function AuthVerifier({
  authToken,
  setAuthToken,
  setAuthVerified,
}: AuthVerifierProps) {
  const [error, setError] = useState("");
  const abortController = useRef<AbortController | null>(null);
  const useOffline = () => {
    if (abortController.current) {
      abortController.current.abort();
    }
    setAuthVerified(true);
  };

  const checkAuth = useCallback(async () => {
    try {
      abortController.current = new AbortController();
      const { data } = await axios.put("/auth", undefined, {
        headers: { Authorization: `Bearer ${authToken}` },
        signal: abortController.current.signal,
      });

      if (isObject(data) && "jwt" in data && typeof data["jwt"] === "string") {
        setAuthVerified(true);
        setAuthToken(data.jwt);
      } else {
        setError("Authentication failed, please log in again.");
        setAuthToken("");
      }
    } catch (error) {
      if (!abortController.current?.signal.aborted) {
        abortController.current = null;
        return;
      }

      console.error(error);
      if (
        isAxiosError(error) &&
        (!window.navigator.onLine || error.code === "ERR_NETWORK")
      ) {
        setAuthVerified(true);
      } else {
        setError("An error occurred while trying to verify authentication.");
      }
    }
  }, [authToken, setAuthToken, setAuthVerified]);

  useEffect(() => {
    checkAuth();
  });

  if (error) {
    return (
      <CenteredHalfAlert
        severity="error"
        action={<LogOutButton size="small" />}
      >
        {error}
      </CenteredHalfAlert>
    );
  } else {
    return (
      <DelayedElement>
        <CenteredHalfAlert
          severity="info"
          action={<Button onClick={useOffline}>Use Offline</Button>}
        >
          Verifying auth...
        </CenteredHalfAlert>
      </DelayedElement>
    );
  }
}

export default AuthVerifier;
