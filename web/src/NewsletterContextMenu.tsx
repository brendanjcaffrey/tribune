import { SortableNewsletter } from "./SortableNewsletter";
import { useEffect, useRef, useState } from "react";
import { WorkerInstance } from "./WorkerInstance";
import { buildMainMessage } from "./WorkerTypes";
import { useAtomValue } from "jotai";
import { showNewsletterFileCallbackAtom } from "./State";

import {
  Book,
  Envelope,
  EnvelopeOpen,
  FileEarmarkText,
  Trash,
} from "react-bootstrap-icons";

export interface NewsletterContextMenuData {
  newsletter: SortableNewsletter;
  mouseX: number;
  mouseY: number;
}

export interface NewsletterContextMenuProps {
  data: NewsletterContextMenuData | null;
  handleClose: () => void;
}

export function NewsletterContextMenu({
  data,
  handleClose,
}: NewsletterContextMenuProps) {
  const showNewsletterFileCallback = useAtomValue(
    showNewsletterFileCallbackAtom,
  );
  const menuRef = useRef<HTMLDivElement>(null);

  const showEpub = () => {
    if (!data) {
      return;
    }
    showNewsletterFileCallback.fn(data.newsletter, "epub");
    handleClose();
  };

  const showSource = () => {
    if (!data) {
      return;
    }
    showNewsletterFileCallback.fn(data.newsletter, "source");
    handleClose();
  };

  const [isRead, setIsRead] = useState(data?.newsletter.read ?? false);
  useEffect(() => {
    if (data) {
      setIsRead(data.newsletter.read);
    }
  }, [data]);

  // close on click outside or escape, mirroring the old mui menu backdrop
  useEffect(() => {
    if (data === null) {
      return;
    }
    const onPointerDown = (event: MouseEvent) => {
      if (menuRef.current && !menuRef.current.contains(event.target as Node)) {
        handleClose();
      }
    };
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        handleClose();
      }
    };
    document.addEventListener("mousedown", onPointerDown);
    document.addEventListener("keydown", onKeyDown);
    return () => {
      document.removeEventListener("mousedown", onPointerDown);
      document.removeEventListener("keydown", onKeyDown);
    };
  }, [data, handleClose]);

  const markAsRead = () => {
    if (!data) {
      return;
    }
    WorkerInstance.postMessage(
      buildMainMessage("mark newsletter as read", {
        id: data.newsletter.id,
      }),
    );
    handleClose();
  };

  const markAsUnread = () => {
    if (!data) {
      return;
    }
    WorkerInstance.postMessage(
      buildMainMessage("mark newsletter as unread", {
        id: data.newsletter.id,
      }),
    );
    handleClose();
  };

  const markDeleted = () => {
    if (!data) {
      return;
    }
    WorkerInstance.postMessage(
      buildMainMessage("mark newsletter as deleted", {
        id: data.newsletter.id,
      }),
    );
    handleClose();
  };

  if (data === null) {
    return null;
  }

  const itemClass = "dropdown-item d-flex align-items-center gap-2";

  return (
    <div
      ref={menuRef}
      className="dropdown-menu show"
      style={{
        position: "fixed",
        top: data.mouseY,
        left: data.mouseX,
        zIndex: 1080,
      }}
    >
      {isRead ? (
        <button className={itemClass} onClick={markAsUnread}>
          <Envelope /> Mark as Unread
        </button>
      ) : (
        <button className={itemClass} onClick={markAsRead}>
          <EnvelopeOpen /> Mark as Read
        </button>
      )}
      <button className={itemClass} onClick={showEpub}>
        <Book /> Open in Reader
      </button>
      <button className={itemClass} onClick={showSource}>
        <FileEarmarkText /> Open Source
      </button>
      <button className={`${itemClass} text-danger`} onClick={markDeleted}>
        <Trash /> Delete
      </button>
    </div>
  );
}
