// lab M4: reads another process's environment through /proc. A real payload
// would harvest secrets this way. Expected: MEM-2.
const fs = require("node:fs");
try { fs.readFileSync("/proc/1/environ"); } catch {}
