import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
export default defineConfig({
  plugins: [react()],
  build: { sourcemap: false },
  server: {
    // Le contenu et le formulaire partagés avec l'API vivent hors de frontend/ (../shared).
    fs: { allow: [".", "../shared"] },
    // En développement, /api est relayé vers l'API locale (backend/contact-api, port 8788).
    proxy: { "/api": process.env.API_PROXY_TARGET || "http://127.0.0.1:8788" },
  },
});
