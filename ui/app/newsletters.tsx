import { Text, View } from "react-native";

import { useAuth } from "@/hooks/useAuth";
import { Redirect } from "expo-router";

export default function Index() {
  const { isLoggedIn, clearAuthState } = useAuth();

  if (!isLoggedIn) {
    return <Redirect href="/sign-in" />;
  }

  return (
    <View style={{ flex: 1, justifyContent: "center", alignItems: "center" }}>
      <Text
        onPress={() => {
          clearAuthState();
        }}
      >
        Sign Out
      </Text>
    </View>
  );
}
