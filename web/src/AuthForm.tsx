import { isObject } from "lodash";
import { useState } from "react";
import axios from "axios";

import Alert from "@mui/material/Alert";
import CircularProgress from "@mui/material/CircularProgress";
import Button from "@mui/material/Button";
import TextField from "@mui/material/TextField";
import Box from "@mui/material/Box";
import Typography from "@mui/material/Typography";
import Container from "@mui/material/Container";

import DelayedElement from "./DelayedElement";

interface AuthFormProps {
  setAuthToken: (authToken: string) => void;
}

function AuthForm({ setAuthToken }: AuthFormProps) {
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [inflight, setInflight] = useState(false);
  const [error, setError] = useState("");

  const handleSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    setInflight(true);
    setError("");

    const formData = new FormData(event.currentTarget);

    try {
      const { data } = await axios.postForm("/auth", formData, {});

      if (isObject(data) && "jwt" in data && typeof data["jwt"] === "string") {
        setAuthToken(data["jwt"]);
      } else {
        console.log(data);
        setError("invalid response from server");
      }
    } catch (error) {
      setError(
        "An error occurred while trying to authenticate. Please try again.",
      );
      console.error(error);
    }
    setInflight(false);
  };

  return (
    <Container component="main" maxWidth="xs">
      <Box
        sx={{
          paddingTop: "40px",
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
        }}
      >
        <Typography component="h1" variant="h5" color="textPrimary">
          Tribune
        </Typography>
        <Box component="form" onSubmit={handleSubmit} noValidate sx={{ mt: 1 }}>
          {error && <Alert severity="error">{error}</Alert>}
          <TextField
            margin="normal"
            required
            fullWidth
            label="Username"
            name="username"
            value={username}
            onChange={(event) => setUsername(event.target.value)}
          />
          <TextField
            margin="normal"
            required
            fullWidth
            label="Password"
            name="password"
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
          />
          <Button
            type="submit"
            fullWidth
            variant="contained"
            sx={{ mt: 3, mb: 2 }}
            disabled={inflight}
          >
            Sign In
            {inflight && (
              <DelayedElement>
                <Box
                  sx={{
                    position: "absolute",
                    top: "50%",
                    left: "50%",
                    transform: "translate(-50%, -50%)",
                  }}
                >
                  <CircularProgress size={37} />
                </Box>
              </DelayedElement>
            )}
          </Button>
        </Box>
      </Box>
    </Container>
  );
}

export default AuthForm;
