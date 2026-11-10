// lab M5: opens another process's memory through /proc, as the TanStack
// malware did. Expected: MEM-2 (or a documented miss if the kernel refuses the
// open before the sensor's hook runs).
const fs = require("node:fs");
try { fs.readFileSync("/proc/1/mem"); } catch {}
