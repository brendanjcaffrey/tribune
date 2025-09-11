import { styled, alpha } from "@mui/material/styles";
import AppBar from "@mui/material/AppBar";
import Box from "@mui/material/Box";
import Toolbar from "@mui/material/Toolbar";
import IconButton from "@mui/material/IconButton";
import Typography from "@mui/material/Typography";
import InputBase from "@mui/material/InputBase";
import SearchRoundedIcon from "@mui/icons-material/SearchRounded";
import DownloadRoundedIcon from "@mui/icons-material/DownloadRounded";
import SettingsRoundedIcon from "@mui/icons-material/SettingsRounded";
import SyncRoundedIcon from "@mui/icons-material/SyncRounded";

import { useAtom, useAtomValue } from "jotai";
import { anyDownloadErrorsAtom, searchAtom } from "./State";
import { useState } from "react";
import { Badge, Tooltip } from "@mui/material";
import DownloadsPanel from "./DownloadsPanel";

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

export default function TopBar() {
  const [search, setSearch] = useAtom(searchAtom);
  const anyDownloadErrors = useAtomValue(anyDownloadErrorsAtom);
  const [showDownloads, setShowDownloads] = useState(false);

  const toggleShowDownloads = () => {
    setShowDownloads((prev) => !prev);
  };

  return (
    <Box sx={{ flexGrow: 1 }}>
      <AppBar position="static">
        <Toolbar>
          <Typography
            variant="h6"
            noWrap
            component="div"
            sx={{ display: { xs: "none", sm: "block" } }}
          >
            Tribune
          </Typography>
          <Box sx={{ flexGrow: 1 }} />
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
            <IconButton size="large" color="inherit">
              <SyncRoundedIcon />
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
            <IconButton size="large" color="inherit">
              <SettingsRoundedIcon />
            </IconButton>
          </Box>
        </Toolbar>
      </AppBar>
      <DownloadsPanel
        showDownloads={showDownloads}
        toggleShowDownloads={toggleShowDownloads}
      />
    </Box>
  );
}
