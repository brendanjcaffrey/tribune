import { Text, View } from "react-native";
import { DataTable, Button } from "react-native-paper";

import { useAuth } from "@/hooks/useAuth";
import { useNewsletters } from "@/hooks/useNewsletters";
import { Redirect } from "expo-router";

export default function Index() {
  const { isLoggedIn, clearAuthState } = useAuth();
  const { newsletters } = useNewsletters();

  if (!isLoggedIn) {
    return <Redirect href="/sign-in" />;
  }

  return (
    <View style={{ flex: 1, padding: 20 }}>
      <Button mode="outlined" onPress={clearAuthState} style={{ marginBottom: 20 }}>
        Sign Out
      </Button>
      <DataTable>
        <DataTable.Header>
          <DataTable.Title>Title</DataTable.Title>
          <DataTable.Title>Author</DataTable.Title>
          <DataTable.Title>Created At</DataTable.Title>
        </DataTable.Header>
        {newsletters.map((n) => (
          <DataTable.Row key={n.id}>
            <DataTable.Cell>{n.title}</DataTable.Cell>
            <DataTable.Cell>{n.author}</DataTable.Cell>
            <DataTable.Cell>{new Date(n.created_at).toLocaleDateString()}</DataTable.Cell>
          </DataTable.Row>
        ))}
      </DataTable>
    </View>
  );
}
