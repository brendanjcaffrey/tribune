import { use, createContext, type PropsWithChildren, useEffect } from "react";
import { useStorageState } from "@/hooks/useStorageState";

interface AuthState {
  jwt: string;
  username: string;
}

const AuthContext = createContext<{
  setAuthState: (auth: AuthState) => void;
  clearAuthState: () => void;
  jwt?: string | null;
  username?: string | null;
  isLoggedIn: boolean;
  isLoading: boolean;
}>({
  setAuthState: (_: AuthState) => null,
  clearAuthState: () => null,
  jwt: null,
  username: null,
  isLoggedIn: false,
  isLoading: false,
});

export function useAuth() {
  const value = use(AuthContext);
  if (!value) {
    throw new Error("useSession must be wrapped in a <SessionProvider />");
  }

  return value;
}

export function AuthProvider({ children }: PropsWithChildren) {
  const [[isLoading, authState], setAuthState] =
    useStorageState<AuthState>("auth");

  return (
    <AuthContext
      value={{
        setAuthState: (auth: AuthState) => {
          setAuthState(auth);
        },
        clearAuthState: () => {
          setAuthState(null);
        },
        jwt: authState?.jwt ?? null,
        username: authState?.username ?? null,
        isLoggedIn: !!authState?.jwt,
        isLoading,
      }}
    >
      {children}
    </AuthContext>
  );
}
