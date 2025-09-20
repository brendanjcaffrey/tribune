import { Provider as JotaiProvider } from "jotai";
import { createTheme, ThemeProvider } from "@mui/material";
import { SnackbarProvider } from "notistack";
import { BackgroundWrapper } from "./BackgroundWrapper";
import AuthWrapper from "./AuthWrapper";
import "./index.css";
import LibraryWrapper from "./LibraryWrapper";
import NewsletterList from "./NewsletterList";
import TopBar from "./TopBar";
import { files } from "./Files";
import { store } from "./State";
import { useState } from "react";
import EpubReader from "./EpubReader";
import { Newsletter } from "./Library";
import Notifier from "./Notifier";
import SettingsRecorder from "./SettingsRecorder";

const theme = createTheme({
  colorSchemes: {
    dark: true,
  },
});

function App() {
  files(); // start initializing now
  const [displayedNewsletter, setDisplayedNewsletter] =
    useState<Newsletter | null>(null);
  const [epubContents, setEpubContents] = useState<ArrayBuffer | null>(null);

  const setNewsletterData = (newsletter: Newsletter, contents: ArrayBuffer) => {
    setDisplayedNewsletter(newsletter);
    setEpubContents(contents);
  };

  const closeNewsletter = () => {
    setDisplayedNewsletter(null);
    setEpubContents(null);
  };

  return (
    <JotaiProvider store={store}>
      <ThemeProvider theme={theme}>
        <BackgroundWrapper>
          <SnackbarProvider maxSnack={3} />
          <Notifier />
          <TopBar />
          <AuthWrapper>
            <LibraryWrapper>
              {(!epubContents || !displayedNewsletter) && (
                <NewsletterList setNewsletterData={setNewsletterData} />
              )}
              {epubContents && displayedNewsletter && (
                <EpubReader
                  newsletter={displayedNewsletter}
                  file={epubContents}
                  closeNewsletter={closeNewsletter}
                />
              )}
            </LibraryWrapper>
          </AuthWrapper>
          <SettingsRecorder />
        </BackgroundWrapper>
      </ThemeProvider>
    </JotaiProvider>
  );
}

export default App;
