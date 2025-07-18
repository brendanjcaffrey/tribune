import { Stack, SplashScreen } from "expo-router";
import { AuthProvider, useAuth } from "@/hooks/useAuth";

export default function Root() {
  // Set up the auth context and render our layout inside of it.
  return (
    <AuthProvider>
      <SplashScreenController />
      <RootNavigator />
    </AuthProvider>
  );
}

function SplashScreenController() {
  const { isLoading } = useAuth();

  if (!isLoading) {
    SplashScreen.hideAsync();
  }

  return null;
}

function RootNavigator() {
  return <Stack></Stack>;
}
