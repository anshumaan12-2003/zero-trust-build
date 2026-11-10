// lab M1: harmless fixture. Opens a direct connection to a reserved
// documentation address (TEST-NET-3), which nothing can answer. The sandbox
// has no route out, so this only ever records the attempt. Expected: NET-1.
const net = require("node:net");
const s = net.connect(443, "203.0.113.10");
s.on("connect", () => s.destroy());
s.on("error", () => {});
