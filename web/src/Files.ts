import { type FileType } from "./WorkerTypes";
import { memoize } from "lodash";

class FileTypeManager {
  type: FileType;
  dirName: string;
  handle: FileSystemDirectoryHandle | null = null;

  constructor(type: FileType, dirName: string) {
    this.type = type;
    this.dirName = dirName;
    this.reset();
  }

  reset() {
    this.handle = null;
    this.fetchHandle();
  }

  isInitialized() {
    return this.handle !== null;
  }

  async fetchHandle() {
    try {
      const mainDir = await navigator.storage.getDirectory();
      const handle = await mainDir.getDirectoryHandle(this.dirName, {
        create: true,
      });
      this.handle = handle;
    } catch (e) {
      console.error(`unable to get ${this.dirName} dir handle`, e);
    }
  }

  async fileExists(id: number): Promise<boolean> {
    try {
      await this.handle!.getFileHandle(id.toString());
      return true;
    } catch {
      return false;
    }
  }

  async tryGetFileURL(id: number): Promise<string | null> {
    try {
      const fileHandle = await this.handle!.getFileHandle(id.toString());
      const file = await fileHandle.getFile();
      return URL.createObjectURL(file);
    } catch {
      return null;
    }
  }

  async tryReadFile(id: number): Promise<File | null> {
    try {
      const fileHandle = await this.handle!.getFileHandle(id.toString());
      return await fileHandle.getFile();
    } catch (e) {
      console.error(e);
      return null;
    }
  }

  async tryWriteFile(
    id: number,
    data: FileSystemWriteChunkType,
  ): Promise<boolean> {
    try {
      const fileHandle = await this.handle!.getFileHandle(id.toString(), {
        create: true,
      });
      const writable = await fileHandle.createWritable();
      await writable.write(data);
      await writable.close();
      return true;
    } catch (e) {
      console.error(e);
      return false;
    }
  }

  async tryDeleteFile(id: number): Promise<boolean> {
    try {
      await this.handle!.removeEntry(id.toString());
      return true;
    } catch {
      return false;
    }
  }

  async getAll(): Promise<Set<string> | undefined> {
    if (!this.handle) {
      return undefined;
    }
    const set = new Set<string>();
    for await (const i of this.handle!.keys()) {
      set.add(i);
    }
    return set;
  }
}

export class Files {
  managers: Map<FileType, FileTypeManager> = new Map();

  constructor() {
    this.managers.set("source", new FileTypeManager("source", "source"));
    this.managers.set("epub", new FileTypeManager("epub", "epub"));
    this.reset();
  }

  reset() {
    for (const manager of this.managers.values()) {
      manager.reset();
    }
  }

  async clearAll() {
    const mainDirHandle = await navigator.storage.getDirectory();
    for (const manager of this.managers.values()) {
      await mainDirHandle.removeEntry(manager.dirName, { recursive: true });
    }
    for (const manager of this.managers.values()) {
      manager.reset();
    }
  }

  allInitialized(): boolean {
    for (const manager of this.managers.values()) {
      if (!manager.isInitialized()) {
        return false;
      }
    }
    return true;
  }

  typeIsInitialized(type: FileType): boolean {
    return this.managers.get(type)?.isInitialized() ?? false;
  }

  async fileExists(type: FileType, id: number): Promise<boolean> {
    return (await this.managers.get(type)?.fileExists(id)) ?? false;
  }

  async tryGetFileURL(type: FileType, id: number): Promise<string | null> {
    return (await this.managers.get(type)?.tryGetFileURL(id)) ?? null;
  }

  async tryReadFile(type: FileType, id: number): Promise<File | null> {
    return (await this.managers.get(type)?.tryReadFile(id)) ?? null;
  }

  async tryWriteFile(
    type: FileType,
    id: number,
    data: FileSystemWriteChunkType,
  ): Promise<boolean> {
    return (await this.managers.get(type)?.tryWriteFile(id, data)) ?? false;
  }

  async tryDeleteFile(type: FileType, id: number): Promise<boolean> {
    return await this.managers.get(type)!.tryDeleteFile(id);
  }

  async getAllOfType(type: FileType): Promise<Set<string> | undefined> {
    const manager = this.managers.get(type);
    if (!manager) {
      return new Set();
    }

    return manager.getAll();
  }
}

export const files = memoize(() => new Files());
