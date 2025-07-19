import { useEffect, useCallback, useReducer } from "react";
import * as FileSystem from "expo-file-system";
import { Platform } from "react-native";

export type UseFileStorageStateHook<T> = [[boolean, T | null], (value: T | null) => void];

function useAsyncState<T>(initialValue: [boolean, T | null] = [true, null]): UseFileStorageStateHook<T> {
  return useReducer(
    (_: [boolean, T | null], action: T | null = null): [boolean, T | null] => [false, action],
    initialValue,
  ) as UseFileStorageStateHook<T>;
}

async function setSerializedItemAsync<T>(key: string, value: T | null): Promise<void> {
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
    const path = `${FileSystem.documentDirectory ?? ""}${key}.json`;
    try {
      if (serialized === null) {
        await FileSystem.deleteAsync(path, { idempotent: true });
      } else {
        await FileSystem.writeAsStringAsync(path, serialized, { encoding: FileSystem.EncodingType.UTF8 });
      }
    } catch (err) {
      console.error("Error writing storage file:", err);
    }
  }
}

export function useFileStorageState<T>(key: string): UseFileStorageStateHook<T> {
  const [state, setState] = useAsyncState<T>();

  useEffect(() => {
    const load = async () => {
      try {
        let raw: string | null = null;
        if (Platform.OS === "web") {
          raw = localStorage.getItem(key);
        } else {
          const path = `${FileSystem.documentDirectory ?? ""}${key}.json`;
          if (await FileSystem.getInfoAsync(path).then((info) => info.exists)) {
            raw = await FileSystem.readAsStringAsync(path, { encoding: FileSystem.EncodingType.UTF8 });
          }
        }
        if (raw != null) {
          try {
            const parsed = JSON.parse(raw) as T;
            setState(parsed);
          } catch (parseError) {
            console.warn(`Failed to parse stored JSON for key "${key}":`, parseError);
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
      setSerializedItemAsync(key, value);
    },
    [key],
  );

  return [state, setValue];
}
