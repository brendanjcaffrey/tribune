import { useState } from "react";
import { Provider as JotaiProvider } from "jotai";

import { BackgroundWrapper } from "./BackgroundWrapper";
import AuthWrapper from "./AuthWrapper";
import LibraryWrapper from "./LibraryWrapper";
import NewsletterList from "./NewsletterList";
import TopBar from "./TopBar";
import { files } from "./Files";
import { store } from "./State";
import EpubReader from "./EpubReader";
import { Newsletter } from "./Library";
import Notifier from "./Notifier";
import Toaster from "./Toaster";
import SettingsRecorder from "./SettingsRecorder";
import "./index.css";

function App() {
  files(); // start initializing now
  const [displayedNewsletter, setDisplayedNewsletter] =
    useState<Newsletter | null>(null);
  const [epubContents, setEpubContents] = useState<ArrayBuffer | null>(null);
  const newsletterShown = !!epubContents && !!displayedNewsletter;

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
      <BackgroundWrapper>
        <Toaster />
        <Notifier />
        <TopBar
          newsletterShown={newsletterShown}
          displayedNewsletter={displayedNewsletter}
          closeNewsletter={closeNewsletter}
        />
        <AuthWrapper>
          <LibraryWrapper>
            {!newsletterShown && (
              <NewsletterList setNewsletterData={setNewsletterData} />
            )}
            {newsletterShown && (
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
    </JotaiProvider>
  );
}

export default App;
