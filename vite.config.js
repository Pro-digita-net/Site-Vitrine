import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
export default defineConfig({
  plugins: [react()],
  build: { sourcemap: false },
  // En développement, /api est relayé vers l'API locale (server/, port 8788).
  server: { proxy: { "/api": process.env.API_PROXY_TARGET || "http://127.0.0.1:8788" } },
});
