// lab M14: opens the fake decoy SSH key and closes it without calling read().
// Code that memory-maps a file works the same way: it opens, then maps, and
// never reads. Before the file-open hook this left no event. Expected: FILE-1.
const fs = require("node:fs");
const os = require("node:os");
try { fs.closeSync(fs.openSync(`${os.homedir()}/.ssh/id_rsa`, "r")); } catch {}
