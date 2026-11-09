import express from "express";

export const quotes = [
  "Trust, but verify.",
  "Security is a process, not a product.",
  "The best time to find a bug is before it ships.",
];

// Builds the app without starting a server, so tests can run it on any port.
export function createApp() {
  const app = express();
  app.disable("x-powered-by");

  app.get("/health", (_req, res) => {
    res.json({ status: "ok" });
  });

  app.get("/quote", (_req, res) => {
    const quote = quotes[Math.floor(Math.random() * quotes.length)];
    res.json({ quote });
  });

  return app;
}
