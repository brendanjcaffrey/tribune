import { useEffect, useCallback, useReducer } from "react";
import * as SecureStore from "expo-secure-store";
import { Platform } from "react-native";

type UseStorageStateHook<T> = [[boolean, T | null], (value: T | null) => void];

function useAsyncState<T>(
  initialValue: [boolean, T | null] = [true, null],
): UseStorageStateHook<T> {
  return useReducer(
    (
      _state: [boolean, T | null],
      action: T | null = null,
    ): [boolean, T | null] => [false, action],
    initialValue,
  ) as UseStorageStateHook<T>;
}

async function setSerializedStorageItemAsync<T>(
  key: string,
  value: T | null,
): Promise<void> {
  const serialized = value === null ? null : JSON.stringify(value);
  if (Platform.OS === "web") {
    try {
      if (serialized === null) {
        localStorage.removeItem(key);
      } else {
        localStorage.setItem(key, serialized);
      }
    } catch (e) {
      console.error("Local storage is unavailable:", e);
    }
  } else {
    if (serialized === null) {
      await SecureStore.deleteItemAsync(key);
    } else {
      await SecureStore.setItemAsync(key, serialized);
    }
  }
}

export function useStorageState<T = any>(key: string): UseStorageStateHook<T> {
  const [state, setState] = useAsyncState<T>();

  useEffect(() => {
    const load = async () => {
      try {
        let raw: string | null = null;

        if (Platform.OS === "web") {
          raw = localStorage.getItem(key);
        } else {
          raw = await SecureStore.getItemAsync(key);
        }

        if (raw != null) {
          try {
            const parsed = JSON.parse(raw) as T;
            setState(parsed);
          } catch (parseError) {
            console.warn(
              `Failed to parse stored JSON for key "${key}":`,
              parseError,
            );
            setState(null);
          }
        } else {
          setState(null);
        }
      } catch (error) {
        console.error("Error accessing storage:", error);
        setState(null);
      }
    };

    load();
  }, [key]);

  const setValue = useCallback(
    (value: T | null) => {
      setState(value);
      setSerializedStorageItemAsync(key, value);
    },
    [key],
  );

  return [state, setValue];
}
