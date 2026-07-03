/**
 * AppShell template — fixed collapsible project-tree sidebar + scrollable main.
 *
 * The sidebar (SessionSidebar) is the primary navigator: projects group their
 * sessions, swarm leads expand to teammates, and an "All activity" entry gives
 * the global cross-project view. Session data comes from SessionIndexProvider.
 */

import type { ReactNode } from "react";
import { SessionSidebar } from "../organisms/SessionSidebar";

export function AppShell({ children }: { children: ReactNode }) {
  return (
    <div style={{ display: "flex", height: "100vh", overflow: "hidden" }}>
      <SessionSidebar />
      <main style={{ flex: 1, padding: 24, overflow: "auto", minWidth: 0 }}>{children}</main>
    </div>
  );
}
