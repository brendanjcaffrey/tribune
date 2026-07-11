import { isObject } from "lodash";
import { useState } from "react";
import axios from "axios";

import Alert from "react-bootstrap/Alert";
import Button from "react-bootstrap/Button";
import Container from "react-bootstrap/Container";
import Form from "react-bootstrap/Form";
import FloatingLabel from "react-bootstrap/FloatingLabel";
import Spinner from "react-bootstrap/Spinner";

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
    <Container
      style={{ maxWidth: "400px", paddingTop: "40px" }}
      className="d-flex flex-column align-items-center"
    >
      <h1 className="h4 mb-3">Tribune</h1>
      <Form onSubmit={handleSubmit} noValidate className="w-100">
        {error && <Alert variant="danger">{error}</Alert>}
        <FloatingLabel controlId="username" label="Username" className="mb-3">
          <Form.Control
            type="text"
            name="username"
            placeholder="Username"
            required
            value={username}
            onChange={(event) => setUsername(event.target.value)}
          />
        </FloatingLabel>
        <FloatingLabel controlId="password" label="Password" className="mb-3">
          <Form.Control
            type="password"
            name="password"
            placeholder="Password"
            required
            value={password}
            onChange={(event) => setPassword(event.target.value)}
          />
        </FloatingLabel>
        <Button
          type="submit"
          className="w-100 position-relative"
          disabled={inflight}
        >
          Sign In
          {inflight && (
            <DelayedElement>
              <span className="position-absolute top-50 start-50 translate-middle">
                <Spinner animation="border" size="sm" />
              </span>
            </DelayedElement>
          )}
        </Button>
      </Form>
    </Container>
  );
}

export default AuthForm;
