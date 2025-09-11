import { memoize } from "lodash";
import { openDB, type DBSchema, type IDBPDatabase } from "idb";

const DATABASE_NAME = "library";
const DATABASE_VERSION = 1;

export interface Newsletter {
  id: number;
  title: string;
  author: string;
  sourceMimeType: string;
  read: boolean;
  deleted: boolean;
  createdAt: string;
  updatedAt: string;
  epubUpdatedAt: string;
  // this is null if never downloaded and will match epubUpdatedAt once downloaded
  epubVersion: string | null;
  // these are set to the time it was first downloaded (on download) and updated whenever the file is opened
  // this is used to decide when to delete old files
  epubLastAccessedAt: string | null;
  sourceLastAccessedAt: string | null;
}

interface LibraryDB extends DBSchema {
  newsletters: {
    key: number;
    value: Newsletter;
  };
}

class Library {
  private db?: IDBPDatabase<LibraryDB>;
  private validState: boolean = true;
  private lastError: string = "";
  private initializedListener?: () => void = undefined;
  private errorListener?: (error: string) => void = undefined;

  public constructor() {
    const setError = this.setError.bind(this);
    openDB<LibraryDB>(DATABASE_NAME, DATABASE_VERSION, {
      upgrade(db) {
        db.createObjectStore("newsletters", { keyPath: "id" });
      },
      blocked(currentVersion, blockedVersion) {
        setError(
          "using database",
          `version ${currentVersion} is blocked by version ${blockedVersion}`,
        );
      },
      blocking(currentVersion, blockedVersion) {
        setError(
          "using database",
          `version ${currentVersion} is blocking version ${blockedVersion}`,
        );
      },
      terminated() {
        setError("using database", "connection terminated");
      },
    })
      .then((db) => {
        this.db = db;
        if (this.initializedListener) {
          this.initializedListener();
        }
      })
      .catch((error) => {
        this.setError("opening database", error);
      });
  }

  public setInitializedListener(listener: () => void) {
    this.initializedListener = listener;
    if (this.db) {
      listener();
    }
  }

  public setErrorListener(listener: (error: string) => void) {
    this.errorListener = listener;
    if (!this.inValidState()) {
      listener(this.lastError);
    }
  }

  public inValidState() {
    return this.validState;
  }

  public getLastError() {
    return this.lastError;
  }

  public async hasAnyNewsletters() {
    if (!this.validState) {
      return false;
    }
    if (!this.db) {
      this.setError("checking store", "database is not initialized");
      return false;
    }

    try {
      return (await this.db.count("newsletters")) > 0;
    } catch (error) {
      this.setError("checking store", error);
      return false;
    }
  }

  public async putNewsletter(newsletter: Newsletter) {
    if (!this.validState) {
      return false;
    }
    if (!this.db) {
      this.setError("put item", "database is not initialized");
      return false;
    }

    try {
      await this.db.put("newsletters", newsletter);
    } catch (error) {
      this.setError("put newsletter", error);
    }
  }

  public async getNewsletter(id: number): Promise<Newsletter | undefined> {
    if (!this.validState) {
      return undefined;
    }
    if (!this.db) {
      this.setError("get newsletters", "database is not initialized");
      return undefined;
    }

    return await this.db.get("newsletters", id);
  }

  public async getAllNewsletters(): Promise<Newsletter[]> {
    if (!this.validState) {
      return [];
    }
    if (!this.db) {
      this.setError("getting newsletters", "database is not initialized");
      return [];
    }

    return await this.db.getAll("newsletters");
  }

  private setError(action: string, error: Error | string | null | unknown) {
    this.validState = false;

    this.lastError = `error while ${action}: `;
    if (error instanceof Error) {
      this.lastError += error.message;
    } else if (error) {
      this.lastError += error;
    } else {
      this.lastError += "unknown error";
    }
    console.error(this.validState, error);
    if (this.errorListener) {
      this.errorListener(this.lastError);
    }
  }
}

const library = memoize(() => new Library());
library();
export default library;
