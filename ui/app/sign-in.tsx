import { Redirect, Stack } from "expo-router";
import React, { useState } from "react";
import {
  View,
  StyleSheet,
  Alert,
  Keyboard,
  TouchableWithoutFeedback,
  KeyboardAvoidingView,
  Platform,
} from "react-native";
import { TextInput, Button, Text } from "react-native-paper";
import { useAuth } from "../hooks/useAuth";

export default function SignIn() {
  const [host, setHost] = useState("");
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const { isLoggedIn, setAuthState } = useAuth();

  if (isLoggedIn) {
    return <Redirect href="/newsletters" />;
  }

  const handleLogin = async () => {
    if (!host || !username || !password) {
      Alert.alert("Missing Fields", "Please fill in all fields.");
      return;
    }

    const endpoint = host.endsWith("/") ? `${host}auth` : `${host}/auth`;
    setLoading(true);

    try {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: `username=${encodeURIComponent(username)}&password=${encodeURIComponent(password)}`,
      });

      if (response.status === 401) {
        Alert.alert("Login Failed", "Invalid credentials. Please try again.");
        return;
      }

      const data = await response.json();

      if (response.ok) {
        setAuthState({ host, jwt: data.jwt, username });
        return null;
      } else {
        Alert.alert("Login Failed", data.message || "Invalid credentials.");
      }
    } catch (error) {
      console.error("Login error:", error);
      Alert.alert("Error", "Could not reach the host or network issue.");
    } finally {
      setLoading(false);
    }
  };

  return (
    <TouchableWithoutFeedback onPress={Keyboard.dismiss}>
      <KeyboardAvoidingView
        behavior={Platform.OS === "ios" ? "padding" : undefined}
        style={{ flex: 1 }}
      >
        <View style={styles.container}>
          <Stack.Screen options={{ title: "Tribune" }} />
          <Text variant="titleLarge" style={styles.title}>
            Login
          </Text>

          <TextInput
            label="Host"
            value={host}
            onChangeText={setHost}
            style={styles.input}
            autoCapitalize="none"
            placeholder="https://example.com:1847"
          />

          <TextInput
            label="Username"
            value={username}
            onChangeText={setUsername}
            style={styles.input}
            autoCapitalize="none"
          />

          <TextInput
            label="Password"
            value={password}
            onChangeText={setPassword}
            style={styles.input}
            secureTextEntry
          />

          <Button
            mode="contained"
            onPress={handleLogin}
            loading={loading}
            disabled={loading}
          >
            Login
          </Button>
        </View>
      </KeyboardAvoidingView>
    </TouchableWithoutFeedback>
  );
}

const styles = StyleSheet.create({
  container: {
    padding: 20,
    justifyContent: "center",
    flex: 1,
  },
  title: {
    marginBottom: 20,
    textAlign: "center",
  },
  input: {
    marginBottom: 10,
  },
});
