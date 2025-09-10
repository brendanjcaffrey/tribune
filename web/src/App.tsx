import { createTheme, ThemeProvider } from "@mui/material";
import { SnackbarProvider } from "notistack";
import { BackgroundWrapper } from "./BackgroundWrapper";
import AuthWrapper from "./AuthWrapper";
import "./index.css";
import LibraryWrapper from "./LibraryWrapper";
import NewsletterList from "./NewsletterList";

const theme = createTheme({
  colorSchemes: {
    dark: true,
  },
});

function App() {
  return (
    <ThemeProvider theme={theme}>
      <BackgroundWrapper>
        <SnackbarProvider maxSnack={3} />
        <AuthWrapper>
          <LibraryWrapper>
            <NewsletterList />
          </LibraryWrapper>
        </AuthWrapper>
      </BackgroundWrapper>
    </ThemeProvider>
  );
}

export default App;
