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

const theme = createTheme({
  colorSchemes: {
    dark: true,
  },
});

function App() {
  files(); // start initializing now
  const [epubContents, setEpubContents] = useState<ArrayBuffer | null>(null);

  return (
    <JotaiProvider store={store}>
      <ThemeProvider theme={theme}>
        <BackgroundWrapper>
          <SnackbarProvider maxSnack={3} />
          <TopBar />
          <AuthWrapper>
            <LibraryWrapper>
              {!epubContents && <NewsletterList setEpubUrl={setEpubContents} />}
              {epubContents && (
                <EpubReader
                  file={epubContents}
                  closeFile={() => setEpubContents(null)}
                />
              )}
            </LibraryWrapper>
          </AuthWrapper>
        </BackgroundWrapper>
      </ThemeProvider>
    </JotaiProvider>
  );
}

export default App;
