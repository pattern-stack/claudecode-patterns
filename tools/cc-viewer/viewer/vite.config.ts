import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      "/admin": { target: "http://localhost:3993", changeOrigin: true },
      "/hooks": { target: "http://localhost:3993", changeOrigin: true },
      "/health": { target: "http://localhost:3993", changeOrigin: true },
    },
  },
});
