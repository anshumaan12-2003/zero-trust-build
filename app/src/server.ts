import { createApp } from "./app";

const port = Number(process.env.PORT ?? 3000);

const server = createApp().listen(port, () => {
  console.log(`Listening on port ${port}`);
});

// In a container, Node runs as process 1, which ignores SIGTERM unless it is
// handled. Without this, Kubernetes waits the full grace period, then kills it.
function shutDown(signal: string) {
  console.log(`${signal} received, finishing open requests`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10_000).unref();
}

process.on("SIGTERM", () => shutDown("SIGTERM"));
process.on("SIGINT", () => shutDown("SIGINT"));
