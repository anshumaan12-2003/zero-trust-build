// lab M3: reads the decoy AWS credentials mounted as $HOME. They are fake.
// Nothing legitimate reads them. Expected: FILE-1.
const fs = require("node:fs");
const os = require("node:os");
try { fs.readFileSync(`${os.homedir()}/.aws/credentials`); } catch {}
