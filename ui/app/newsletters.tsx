import { View, FlatList, RefreshControl, AppState } from "react-native";
import { List, IconButton, Searchbar, Icon } from "react-native-paper";

import { useAuth } from "../hooks/useAuth";
import { useNewsletters, parseTimestamp } from "../hooks/useNewsletters";
import { Redirect, Stack, useFocusEffect } from "expo-router";
import { useCallback, useEffect, useRef, useState } from "react";

const statusIcons: Record<"pending" | "downloading" | "downloaded", string> = {
  pending: "cloud-download-outline",
  downloading: "progress-download",
  downloaded: "check-circle-outline",
};

export default function Index() {
  const { isLoggedIn, clearAuthState } = useAuth();
  const {
    newsletters,
    syncInProgress: newsletterSyncInProgress,
    clear: clearNewsletters,
    sync: syncNewsletters,
  } = useNewsletters();
  const [filteredNewsletters, setFilteredNewsletters] = useState(newsletters);
  const [searchText, setSearchText] = useState("");
  const appState = useRef(AppState.currentState);

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

  useFocusEffect(
    useCallback(() => {
      syncNewsletters();
    }, [syncNewsletters]),
  );

  useEffect(() => {
    const subscription = AppState.addEventListener("change", (nextAppState) => {
      if (
        appState.current.match(/inactive|background/) &&
        nextAppState === "active"
      ) {
        syncNewsletters();
      }

      appState.current = nextAppState;
    });

    return () => {
      subscription.remove();
    };
  }, [syncNewsletters]);

  if (!isLoggedIn) {
    return <Redirect href="/sign-in" />;
  }

  let logout = () => {
    clearAuthState();
    clearNewsletters();
  };

  return (
    <View style={{ flex: 1, padding: 4 }}>
      <Stack.Screen
        options={{
          title: "Newsletters",
          headerLeft: () => (
            <IconButton
              icon="logout"
              onPress={logout}
              disabled={newsletterSyncInProgress}
            />
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
        refreshControl={
          <RefreshControl
            refreshing={newsletterSyncInProgress}
            onRefresh={syncNewsletters}
          />
        }
        renderItem={({ item }) => (
          <List.Item
            description={`${item.author} • ${parseTimestamp(item.created_at).toLocaleDateString()}`}
            title={item.title}
            titleNumberOfLines={0}
            descriptionNumberOfLines={0}
            right={() => (
              <Icon
                source={statusIcons[item.downloadStatus ?? "pending"]}
                size={20}
              />
            )}
          />
        )}
      />
    </View>
  );
}
