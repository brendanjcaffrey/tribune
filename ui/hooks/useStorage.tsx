import { useEffect, useCallback, useReducer } from "react";
import * as SecureStore from "expo-secure-store";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { Platform } from "react-native";

// matches the SecureStore interface
interface StorageAdapter {
  getItemAsync(key: string): Promise<string | null>;
  deleteItemAsync(key: string): Promise<void>;
  setItemAsync(key: string, value: string): Promise<void>;
}

class AsyncStorageAdapter {
  static async getItemAsync(key: string): Promise<string | null> {
    return await AsyncStorage.getItem(key);
  }

  static async deleteItemAsync(key: string): Promise<void> {
    return await AsyncStorage.removeItem(key);
  }

  static async setItemAsync(key: string, value: string): Promise<void> {
    return await AsyncStorage.setItem(key, value);
  }
}

class LocalStorageAdapter {
  static async getItemAsync(key: string): Promise<string | null> {
    return localStorage.getItem(key);
  }
  static async deleteItemAsync(key: string): Promise<void> {
    localStorage.removeItem(key);
  }
  static async setItemAsync(key: string, value: string): Promise<void> {
    localStorage.setItem(key, value);
  }
}

type UseStorageHook<T> = [[boolean, T | null], (value: T | null) => void];

function useAsyncState<T>(
  initialValue: [boolean, T | null] = [true, null],
): UseStorageHook<T> {
  return useReducer(
    (
      _state: [boolean, T | null],
      action: T | null = null,
    ): [boolean, T | null] => [false, action],
    initialValue,
  ) as UseStorageHook<T>;
}

function useGenericStorage<T = any>(
  key: string,
  adapter: StorageAdapter,
): UseStorageHook<T> {
  const [state, setState] = useAsyncState<T>();

  useEffect(() => {
    const load = async () => {
      try {
        let raw: string | null = await adapter.getItemAsync(key);

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
    async (value: T | null) => {
      setState(value);
      const serialized = value === null ? null : JSON.stringify(value);
      try {
        if (serialized === null) {
          await adapter.deleteItemAsync(key);
        } else {
          await adapter.setItemAsync(key, serialized);
        }
      } catch (e) {
        console.error("Unable to set storage value:", e);
      }
    },
    [key],
  );

  return [state, setValue];
}

export function useStorage<T = any>(key: string): UseStorageHook<T> {
  const adapter: StorageAdapter =
    Platform.OS === "web" ? LocalStorageAdapter : AsyncStorageAdapter;
  return useGenericStorage<T>(key, adapter);
}

export function useSecureStorage<T = any>(key: string): UseStorageHook<T> {
  const adapter: StorageAdapter =
    Platform.OS === "web" ? LocalStorageAdapter : SecureStore;
  return useGenericStorage<T>(key, adapter);
}
