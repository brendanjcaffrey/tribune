import { useAtomValue } from "jotai";
import Toast from "react-bootstrap/Toast";
import ToastContainer from "react-bootstrap/ToastContainer";
import { toastsAtom, dismissToast, type ToastVariant } from "./Toasts";

const variantToBg: Record<ToastVariant, string> = {
  info: "info",
  error: "danger",
  success: "success",
};

// bootstrap's info background is light, so it wants dark text; the others are
// dark enough for white text.
const variantToTextClass: Record<ToastVariant, string> = {
  info: "",
  error: "text-white",
  success: "text-white",
};

function Toaster() {
  const toasts = useAtomValue(toastsAtom);

  return (
    <ToastContainer
      position="bottom-start"
      className="p-3 position-fixed"
      style={{ zIndex: 1100 }}
    >
      {toasts.map((toast) => (
        <Toast
          key={toast.id}
          bg={variantToBg[toast.variant]}
          onClose={() => dismissToast(toast.id)}
          delay={toast.autoHideDuration}
          autohide
        >
          <Toast.Body className={variantToTextClass[toast.variant]}>
            {toast.message}
          </Toast.Body>
        </Toast>
      ))}
    </ToastContainer>
  );
}

export default Toaster;
