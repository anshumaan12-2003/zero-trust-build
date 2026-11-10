// lab M11: tunnels through the proxy to the one allowed domain, carrying data
// in the request. The proxy permits registry.npmjs.org, so nothing flags it.
// Expected miss: an allow-listed host can still be a covert channel.
const http = require("node:http");
http
  .request({ host: "ztb-proxy", port: 3128, method: "CONNECT", path: "registry.npmjs.org:443" })
  .on("connect", (res, socket) => socket.end())
  .on("error", () => {})
  .end();
