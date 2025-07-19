import { View, FlatList } from "react-native";
import { List, IconButton, Searchbar, Icon } from "react-native-paper";

import { useAuth } from "@/hooks/useAuth";
import { useNewsletters, parseTimestamp } from "@/hooks/useNewsletters";
import { Redirect, Stack } from "expo-router";
import { useEffect, useState } from "react";

export default function Index() {
  const { isLoggedIn, clearAuthState } = useAuth();
  const { newsletters } = useNewsletters();
  const [filteredNewsletters, setFilteredNewsletters] = useState(newsletters);
  const [searchText, setSearchText] = useState("");

  useEffect(() => {
    if (searchText) {
      const filtered = newsletters.filter((n) =>
        n.title.toLowerCase().includes(searchText.toLowerCase()),
      );
      setFilteredNewsletters(filtered);
    } else {
      setFilteredNewsletters(newsletters);
    }
  }, [searchText, newsletters]);

  if (!isLoggedIn) {
    return <Redirect href="/sign-in" />;
  }

  return (
    <View style={{ flex: 1, padding: 4 }}>
      <Stack.Screen
        options={{
          title: "Newsletters",
          headerLeft: () => (
            <IconButton icon="logout" onPress={clearAuthState} />
          ),
        }}
      />
      <Searchbar
        placeholder="Search"
        onChangeText={setSearchText}
        value={searchText}
      />
      <FlatList
        data={filteredNewsletters}
        keyExtractor={(n) => n.id.toString()}
        renderItem={({ item }) => (
          <List.Item
            description={`${item.author} • ${parseTimestamp(item.created_at).toLocaleDateString()}`}
            title={item.title}
            titleNumberOfLines={0}
            descriptionNumberOfLines={0}
          />
        )}
      />
    </View>
  );
}
