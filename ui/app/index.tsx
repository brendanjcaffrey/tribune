import { useAuth } from "@/hooks/useAuth";
import { Redirect } from "expo-router";

export default function Index() {
  const { isLoggedIn } = useAuth();

  return <Redirect href={isLoggedIn ? "/newsletters" : "/sign-in"} />;
}
