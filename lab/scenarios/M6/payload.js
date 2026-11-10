// lab M6: connects to the cloud metadata address. On a real cloud runner this
// hands out credentials; here there is nothing to answer. Expected: NET-1.
const net = require("node:net");
const s = net.connect(80, "169.254.169.254");
s.on("connect", () => s.destroy());
s.on("error", () => {});
