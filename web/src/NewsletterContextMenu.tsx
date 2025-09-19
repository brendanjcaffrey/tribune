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
        <MenuItem>
          <ListItemIcon>
            <Book fontSize="small" />
          </ListItemIcon>
          <ListItemText>Open ePub</ListItemText>
        </MenuItem>
        <MenuItem>
          <ListItemIcon>
            <Source fontSize="small" />
          </ListItemIcon>
          <ListItemText>Open Source</ListItemText>
        </MenuItem>
        <MenuItem>
          <ListItemIcon>
            <Delete fontSize="small" color="error" />
          </ListItemIcon>
          <ListItemText>Delete</ListItemText>
        </MenuItem>
      </Menu>
    </>
  );
}
