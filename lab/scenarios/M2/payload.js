// lab M2: asks the proxy for a domain that is not on the allow list. The proxy
// refuses it and logs the denial. Expected: NET-2. evil.invalid can never
// resolve to a real host.
const http = require("node:http");
http
  .request({ host: "ztb-proxy", port: 3128, method: "CONNECT", path: "evil.invalid:443" })
  .on("connect", (res, socket) => socket.end())
  .on("error", () => {})
  .end();
