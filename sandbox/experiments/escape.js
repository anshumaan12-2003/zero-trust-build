// Harmless escape test, run as an install script inside the sandbox.
// 203.0.113.10 is a reserved documentation address, so nothing can answer.
// The credentials it reads are the fake decoys.
const fs = require("node:fs");
const http = require("node:http");
const net = require("node:net");
const os = require("node:os");

const direct = net.connect(443, "203.0.113.10");
direct.on("connect", () => {
  console.log("1. direct connection: CONNECTED (the sandbox leaked)");
  direct.destroy();
});
direct.on("error", (error) => console.log(`1. direct connection: blocked (${error.code})`));

http
  .request({ host: "ztb-proxy", port: 3128, method: "CONNECT", path: "example.com:443" })
  .on("connect", (response) => console.log(`2. proxy to example.com: HTTP ${response.statusCode}`))
  .on("error", (error) => console.log(`2. proxy to example.com: error (${error.code})`))
  .end();

try {
  fs.readFileSync(`${os.homedir()}/.aws/credentials`);
  console.log("3. decoy credentials: read");
} catch (error) {
  console.log(`3. decoy credentials: not read (${error.code})`);
}
