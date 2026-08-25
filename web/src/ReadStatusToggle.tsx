import { useCallback, useEffect, useState } from "react";
import Button from "react-bootstrap/Button";
import OverlayTrigger from "react-bootstrap/OverlayTrigger";
import Tooltip from "react-bootstrap/Tooltip";
import { Envelope, EnvelopeOpenFill } from "react-bootstrap-icons";

import library from "./Library";
import { WorkerInstance } from "./WorkerInstance";
import { buildMainMessage } from "./WorkerTypes";

interface ReadStatusToggleProps {
  newsletterId: number;
  initiallyRead: boolean;
}

// shows whether the open newsletter is read and lets it be flipped either way. the
// reader marks it read on its own once the end of the document is reached, so the
// state is re-read from the library whenever the worker says something changed
export default function ReadStatusToggle({
  newsletterId,
  initiallyRead,
}: ReadStatusToggleProps) {
  const [isRead, setIsRead] = useState(initiallyRead);

  useEffect(() => {
    setIsRead(initiallyRead);
  }, [newsletterId, initiallyRead]);

  const refresh = useCallback(async () => {
    const newsletter = await library().getNewsletter(newsletterId);
    if (newsletter) {
      setIsRead(newsletter.read);
    }
  }, [newsletterId]);

  useEffect(() => {
    const listener = WorkerInstance.addMessageListener(async (message) => {
      if (message.type === "newsletters updated") {
        await refresh();
      }
    });
    refresh();
    return () => {
      WorkerInstance.removeMessageListener(listener);
    };
  }, [refresh]);

  const toggle = () => {
    if (isRead) {
      WorkerInstance.postMessage(
        buildMainMessage("mark newsletter as unread", { id: newsletterId }),
      );
    } else {
      WorkerInstance.postMessage(
        buildMainMessage("mark newsletter as read", { id: newsletterId }),
      );
    }
    // the worker echoes back a newsletters updated message, but flip right away so
    // the button doesn't lag behind the click
    setIsRead(!isRead);
  };

  return (
    <OverlayTrigger
      placement="bottom"
      overlay={<Tooltip>{isRead ? "Mark as Unread" : "Mark as Read"}</Tooltip>}
    >
      <Button
        variant="link"
        className="text-white p-1 flex-shrink-0"
        onClick={toggle}
        aria-label={isRead ? "mark as unread" : "mark as read"}
        aria-pressed={isRead}
      >
        {isRead ? <EnvelopeOpenFill size={18} /> : <Envelope size={18} />}
      </Button>
    </OverlayTrigger>
  );
}
