import { useEffect, useState } from "react";
import { useAtom, useAtomValue } from "jotai";
import { anyDownloadErrorsAtom, authVerifiedAtom, searchAtom } from "./State";
import DownloadsPanel from "./DownloadsPanel";
import SettingsPanel from "./SettingsPanel";
import { WorkerInstance } from "./WorkerInstance";
import { buildMainMessage } from "./WorkerTypes";

import { styled, alpha } from "@mui/material/styles";
import AppBar from "@mui/material/AppBar";
import Badge from "@mui/material/Badge";
import Box from "@mui/material/Box";
import IconButton from "@mui/material/IconButton";
import InputBase from "@mui/material/InputBase";
import Toolbar from "@mui/material/Toolbar";
import Tooltip from "@mui/material/Tooltip";
import Typography from "@mui/material/Typography";

import CloseRoundedIcon from "@mui/icons-material/CloseRounded";
import DownloadRoundedIcon from "@mui/icons-material/DownloadRounded";
import SearchRoundedIcon from "@mui/icons-material/SearchRounded";
import SettingsRoundedIcon from "@mui/icons-material/SettingsRounded";
import SyncRoundedIcon from "@mui/icons-material/SyncRounded";
import { Newsletter } from "./Library";

const Search = styled("div")(({ theme }) => ({
  position: "relative",
  borderRadius: theme.shape.borderRadius,
  backgroundColor: alpha(theme.palette.common.white, 0.15),
  "&:hover": {
    backgroundColor: alpha(theme.palette.common.white, 0.25),
  },
  marginRight: theme.spacing(2),
  marginLeft: 0,
  width: "100%",
  [theme.breakpoints.up("sm")]: {
    marginLeft: theme.spacing(3),
    width: "auto",
  },
}));

const SearchIconWrapper = styled("div")(({ theme }) => ({
  padding: theme.spacing(0, 2),
  height: "100%",
  position: "absolute",
  pointerEvents: "none",
  display: "flex",
  alignItems: "center",
  justifyContent: "center",
}));

const StyledInputBase = styled(InputBase)(({ theme }) => ({
  color: "inherit",
  "& .MuiInputBase-input": {
    padding: theme.spacing(1, 1, 1, 0),
    // vertical padding + font size from searchIcon
    paddingLeft: `calc(1em + ${theme.spacing(4)})`,
    transition: theme.transitions.create("width"),
    width: "100%",
    [theme.breakpoints.up("md")]: {
      width: "20ch",
    },
  },
}));

interface TopBarProps {
  newsletterShown: boolean;
  displayedNewsletter: Newsletter | null;
  closeNewsletter: () => void;
}

export default function TopBar({
  newsletterShown,
  displayedNewsletter,
  closeNewsletter,
}: TopBarProps) {
  const [search, setSearch] = useAtom(searchAtom);
  const anyDownloadErrors = useAtomValue(anyDownloadErrorsAtom);
  const [showDownloads, setShowDownloads] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [syncRunning, setSyncRunning] = useState(false);
  const authVerified = useAtomValue(authVerifiedAtom);

  const toggleShowDownloads = () => {
    setShowDownloads((prev) => !prev);
  };

  const toggleShowSettings = () => {
    setShowSettings((prev) => !prev);
  };

  const startSync = () => {
    WorkerInstance.postMessage(
      buildMainMessage("start sync", { background: false }),
    );
  };

  useEffect(() => {
    if (!authVerified) {
      setShowDownloads(false);
      setShowSettings(false);
    }
  }, [authVerified]);

  useEffect(() => {
    const listener = WorkerInstance.addMessageListener(async (message) => {
      if (message.type === "sync status") {
        setSyncRunning(message.running);
      }
    });
    return () => {
      WorkerInstance.removeMessageListener(listener);
    };
  }, []);

  useEffect(() => {
    if (authVerified) {
      const handleFocus = () => {
        WorkerInstance.postMessage(
          buildMainMessage("start sync", { background: true }),
        );
      };
      window.addEventListener("focus", handleFocus);
      return () => window.removeEventListener("focus", handleFocus);
    }
  }, [authVerified]);

  return (
    <Box sx={{ flexGrow: 1 }}>
      <AppBar position="static">
        <Toolbar>
          <Typography variant="h6" noWrap component="div">
            {newsletterShown && displayedNewsletter
              ? displayedNewsletter.title
              : "Tribune"}
          </Typography>
          <Box sx={{ flexGrow: 1 }} />
          {authVerified && !newsletterShown && (
            <>
              <Search>
                <SearchIconWrapper>
                  <SearchRoundedIcon />
                </SearchIconWrapper>
                <StyledInputBase
                  placeholder="Search…"
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  inputProps={{ "aria-label": "search" }}
                />
              </Search>
              <Box sx={{ display: { xs: "none", md: "flex" } }}>
                <IconButton size="large" color="inherit" onClick={startSync}>
                  {syncRunning ? (
                    <SyncRoundedIcon
                      sx={{
                        animation: "spin 2s linear infinite",
                        "@keyframes spin": {
                          "0%": {
                            transform: "rotate(360deg)",
                          },
                          "100%": {
                            transform: "rotate(0deg)",
                          },
                        },
                      }}
                    />
                  ) : (
                    <SyncRoundedIcon />
                  )}
                </IconButton>
                <Tooltip title="Download Status">
                  <IconButton
                    size="large"
                    color="inherit"
                    onClick={toggleShowDownloads}
                  >
                    <Badge
                      color="error"
                      variant="dot"
                      invisible={!anyDownloadErrors}
                    >
                      <DownloadRoundedIcon />
                    </Badge>
                  </IconButton>
                </Tooltip>
                <IconButton
                  size="large"
                  color="inherit"
                  onClick={toggleShowSettings}
                >
                  <SettingsRoundedIcon />
                </IconButton>
              </Box>
            </>
          )}
          {authVerified && newsletterShown && (
            <Box sx={{ display: { md: "flex" } }}>
              <IconButton
                size="large"
                color="inherit"
                onClick={closeNewsletter}
              >
                <CloseRoundedIcon />
              </IconButton>
            </Box>
          )}
        </Toolbar>
      </AppBar>
      <DownloadsPanel
        showDownloads={showDownloads}
        toggleShowDownloads={toggleShowDownloads}
      />
      <SettingsPanel
        showSettings={showSettings}
        toggleShowSettings={toggleShowSettings}
      />
    </Box>
  );
}
