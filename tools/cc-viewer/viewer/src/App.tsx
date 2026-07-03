import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
import { AppShell } from "./components/templates/AppShell";
import { SessionIndexProvider } from "./hooks/useSessionIndex";
import { ChatPage } from "./pages/ChatPage";
import { ChatSessionPage } from "./pages/ChatSessionPage";
import { LogsPage } from "./pages/LogsPage";

export function App() {
  return (
    <BrowserRouter>
      <SessionIndexProvider>
        <AppShell>
          <Routes>
            <Route path="/" element={<Navigate to="/chat" replace />} />
            <Route path="/logs" element={<LogsPage />} />
            <Route path="/chat" element={<ChatPage />} />
            <Route path="/chat/:sessionId" element={<ChatSessionPage />} />
          </Routes>
        </AppShell>
      </SessionIndexProvider>
    </BrowserRouter>
  );
}
