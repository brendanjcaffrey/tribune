import { Stack, SplashScreen } from "expo-router";
import { AuthProvider, useAuth } from "@/hooks/useAuth";
import { NewslettersProvider } from "@/hooks/useNewsletters";

export default function Root() {
  // Set up the auth context and render our layout inside of it.
  return (
    <AuthProvider>
      <NewslettersProvider>
        <SplashScreenController />
        <RootNavigator />
      </NewslettersProvider>
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
