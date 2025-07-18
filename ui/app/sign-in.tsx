import { Redirect } from "expo-router";
import { Text, View } from "react-native";

import { useAuth } from "@/hooks/useAuth";

export default function SignIn() {
  const { isLoggedIn, signIn } = useAuth();

  if (isLoggedIn) {
    return <Redirect href="/newsletters" />;
  }

  return (
    <View style={{ flex: 1, justifyContent: "center", alignItems: "center" }}>
      <Text
        onPress={() => {
          signIn({ username: "me", jwt: "1234" });
        }}
      >
        Sign In
      </Text>
    </View>
  );
}
