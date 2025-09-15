import { useState, useEffect } from "react";
import {
  Dialog,
  DialogTitle,
  DialogContent,
  Popover,
  Tooltip,
  Grid,
  FormControlLabel,
  Switch,
  IconButton,
} from "@mui/material";
import { enqueueSnackbar } from "notistack";
import { formatBytes } from "./Util";
import LogOutButton from "./LogOutButton";
import { HelpOutlineRounded } from "@mui/icons-material";

interface SettingsPanelProps {
  showSettings: boolean;
  toggleShowSettings: () => void;
}

function SettingsPanel({
  showSettings,
  toggleShowSettings,
}: SettingsPanelProps) {
  const [persisted, setPersisted] = useState(false);

  const [persistStorageHelpAnchorEl, setPersistStorageHelpAnchorEl] =
    useState<HTMLButtonElement | null>(null);
  const persistStorageHelpOpen = Boolean(persistStorageHelpAnchorEl);

  const handlePersistStorageChange = (
    event: React.ChangeEvent<HTMLInputElement>,
  ) => {
    if (persisted || !event.target.checked) {
      return;
    }
    navigator.storage.persist().then((granted) => {
      if (granted) {
        setPersisted(true);
      } else {
        enqueueSnackbar("Persistent storage was not granted.", {
          variant: "error",
        });
      }
    });
  };

  const openPersistStorageHelp = (
    event: React.MouseEvent<HTMLButtonElement>,
  ) => {
    setPersistStorageHelpAnchorEl(event.currentTarget);
  };

  const closePersistStorageHelp = () => {
    setPersistStorageHelpAnchorEl(null);
  };

  const [usage, setUsage] = useState(0);
  const [quota, setQuota] = useState(1);
  const percentageUsed = ((usage / quota) * 100).toFixed(2);

  useEffect(() => {
    const fetchStorageInfo = async () => {
      if (navigator.storage && navigator.storage.estimate) {
        const { usage, quota } = await navigator.storage.estimate();
        setUsage(usage || 0);
        setQuota(quota || 1);
      }

      if (navigator.storage && (await navigator.storage.persisted())) {
        setPersisted(true);
      } else {
        setPersisted(false);
      }
    };

    fetchStorageInfo();
    const interval = setInterval(fetchStorageInfo, 5000);

    return () => clearInterval(interval);
  }, []);

  return (
    <Dialog open={showSettings} onClose={toggleShowSettings}>
      <DialogTitle>Settings</DialogTitle>
      <DialogContent>
        <Grid container spacing={0} sx={{ width: "300px" }}>
          <Grid size={10}>
            <FormControlLabel
              control={
                <Switch
                  checked={persisted}
                  disabled={persisted}
                  onChange={handlePersistStorageChange}
                />
              }
              label="Persist Storage"
            />
          </Grid>
          <Grid size={2}>
            <IconButton onClick={openPersistStorageHelp}>
              <HelpOutlineRounded sx={{ float: "right" }} />
            </IconButton>
          </Grid>
          <Grid container spacing={0} sx={{ width: "300px" }}>
            <Grid size={12}>
              <Tooltip title={`${formatBytes(usage)} / ${formatBytes(quota)}`}>
                <p>Storage Used: {percentageUsed}%</p>
              </Tooltip>
            </Grid>
            <Grid size={12}>
              <LogOutButton />
            </Grid>
          </Grid>
        </Grid>
        <Popover
          open={persistStorageHelpOpen}
          anchorEl={persistStorageHelpAnchorEl}
          onClose={closePersistStorageHelp}
          anchorOrigin={{
            vertical: "bottom",
            horizontal: "left",
          }}
        >
          <div style={{ padding: "10px", maxWidth: "300px" }}>
            Request that the browser allow this app to store data persistently
            and give it a larger quota. Firefox will prompt you to allow this,
            but Chrome may not allow this until you use the app more. Once
            granted, it is not possible to revoke this permission.
          </div>
        </Popover>
      </DialogContent>
    </Dialog>
  );
}

export default SettingsPanel;
