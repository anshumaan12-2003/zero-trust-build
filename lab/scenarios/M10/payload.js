// lab M10: slips an extra, unreviewed file into node_modules, which the build
// copies into the released image. The judge checks behaviour, not output
// contents, so this is an expected miss.
const fs = require("node:fs");
try { fs.writeFileSync("node_modules/.lab-extra.js", "// lab M10: unreviewed extra file\n"); } catch {}
