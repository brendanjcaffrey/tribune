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
          <MenuItem>
            <ListItemIcon>
              <MarkEmailUnread fontSize="small" />
            </ListItemIcon>
            <ListItemText>Mark as Unread</ListItemText>
          </MenuItem>
        )}
        {!isRead && (
          <MenuItem>
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
