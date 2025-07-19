import { View, FlatList } from "react-native";
import { List, Button } from "react-native-paper";

import { useAuth } from "@/hooks/useAuth";
import { useNewsletters, parseTimestamp } from "@/hooks/useNewsletters";
import { Redirect } from "expo-router";

export default function Index() {
  const { isLoggedIn, clearAuthState } = useAuth();
  const { newsletters } = useNewsletters();

  if (!isLoggedIn) {
    return <Redirect href="/sign-in" />;
  }

  return (
    <View style={{ flex: 1, padding: 20 }}>
      <Button
        mode="outlined"
        onPress={clearAuthState}
        style={{ marginBottom: 20 }}
      >
        Sign Out
      </Button>
      <FlatList
        data={newsletters}
        keyExtractor={(n) => n.id.toString()}
        renderItem={({ item }) => (
          <List.Item
            title={item.title}
            description={`${item.author} • ${parseTimestamp(item.created_at).toLocaleDateString()}`}
          />
        )}
      />
    </View>
  );
}
