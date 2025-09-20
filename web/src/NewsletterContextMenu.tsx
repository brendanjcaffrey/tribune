import { Menu, MenuItem, ListItemIcon, ListItemText } from "@mui/material";
import {
  MarkEmailUnread,
  MarkEmailRead,
  Book,
  Source,
  Delete,
} from "@mui/icons-material";
import { SortableNewsletter } from "./SortableNewsletter";
import { useEffect, useState } from "react";
import { WorkerInstance } from "./WorkerInstance";
import { buildMainMessage } from "./WorkerTypes";
import { useAtomValue } from "jotai";
import { showNewsletterFileCallbackAtom } from "./State";

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

  return (
    <>
      <Menu
        open={data !== null}
        onClose={handleClose}
        anchorReference="anchorPosition"
        anchorPosition={
          data !== null ? { top: data.mouseY, left: data.mouseX } : undefined
        }
        variant="menu"
        autoFocus={false}
        slotProps={{
          list: { dense: true },
        }}
      >
        {isRead && (
          <MenuItem onClick={markAsUnread}>
            <ListItemIcon>
              <MarkEmailUnread fontSize="small" />
            </ListItemIcon>
            <ListItemText>Mark as Unread</ListItemText>
          </MenuItem>
        )}
        {!isRead && (
          <MenuItem onClick={markAsRead}>
            <ListItemIcon>
              <MarkEmailRead fontSize="small" />
            </ListItemIcon>
            <ListItemText>Mark as Read</ListItemText>
          </MenuItem>
        )}
        <MenuItem onClick={showEpub}>
          <ListItemIcon>
            <Book fontSize="small" />
          </ListItemIcon>
          <ListItemText>Open ePub</ListItemText>
        </MenuItem>
        <MenuItem onClick={showSource}>
          <ListItemIcon>
            <Source fontSize="small" />
          </ListItemIcon>
          <ListItemText>Open Source</ListItemText>
        </MenuItem>
        <MenuItem onClick={markDeleted}>
          <ListItemIcon>
            <Delete fontSize="small" color="error" />
          </ListItemIcon>
          <ListItemText>Delete</ListItemText>
        </MenuItem>
      </Menu>
    </>
  );
}
