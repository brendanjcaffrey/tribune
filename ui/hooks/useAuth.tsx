import { use, createContext, type PropsWithChildren } from "react";
import { useStorageState } from "@/hooks/useStorageState";

interface AuthState {
  host: string;
  jwt: string;
  username: string;
}

const AuthContext = createContext<{
  setAuthState: (auth: AuthState) => void;
  clearAuthState: () => void;
  state: AuthState | null;
  isLoggedIn: boolean;
  isLoading: boolean;
}>({
  setAuthState: (_: AuthState) => null,
  clearAuthState: () => null,
  state: null,
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
        state: authState ?? null,
        isLoggedIn: !!authState?.jwt,
        isLoading,
      }}
    >
      {children}
    </AuthContext>
  );
}
