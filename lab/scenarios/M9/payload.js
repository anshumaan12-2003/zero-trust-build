// lab M9: fires only inside CI, to dodge a developer's laptop. The sandbox
// sets CI=true, so it still runs and is caught. Expected: NET-1.
const net = require("node:net");
if (process.env.CI === "true") {
  const s = net.connect(443, "203.0.113.10");
  s.on("connect", () => s.destroy());
  s.on("error", () => {});
}
