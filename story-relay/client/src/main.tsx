import { createRoot } from "react-dom/client";
import App from "./App";
import "./index.css";

type BootstrapWindow = Window & {
  __storyRelayShowStartupFallback?: () => void;
};

function showBootstrapFailure(error: unknown) {
  console.error("Story Relay bootstrap failed:", error);

  const root = document.getElementById("root");
  if (!root) return;

  root.replaceChildren();
  const fallback = (window as BootstrapWindow).__storyRelayShowStartupFallback;
  if (fallback) {
    fallback();
    return;
  }

  root.textContent = "Story Relay 無法啟動，請重新載入頁面。";
}

try {
  const root = document.getElementById("root");
  if (!root) throw new Error("Missing #root element");
  createRoot(root).render(<App />);
} catch (error) {
  showBootstrapFailure(error);
}
