import { type ReactNode } from "react";
import Alert from "react-bootstrap/Alert";

type Severity = "error" | "info" | "success" | "warning";

const severityToVariant: Record<Severity, string> = {
  error: "danger",
  info: "info",
  success: "success",
  warning: "warning",
};

interface CenteredHalfAlertProps {
  severity?: Severity;
  action?: ReactNode;
  children: ReactNode;
}

function CenteredHalfAlert({
  severity = "info",
  action,
  children,
}: CenteredHalfAlertProps) {
  return (
    <Alert
      variant={severityToVariant[severity]}
      style={{ width: "50%", marginLeft: "25%", marginTop: "12px" }}
      className="d-flex justify-content-between align-items-center"
    >
      <div>{children}</div>
      {action}
    </Alert>
  );
}

export default CenteredHalfAlert;
