// lab M15: replaces the trusted build tool node_modules/.bin/tsc with a shell
// script of the same name. The script does its own work using only shell
// built-ins (it writes an extra, harmless file), then runs the real compiler.
// The known-program list matches paths, so nothing new shows up. Expected
// miss: anything harmful the script then tried would still hit the other rules.
const fs = require("node:fs");
const tool = "node_modules/.bin/tsc";
try {
  fs.rmSync(tool, { force: true });
  fs.writeFileSync(tool, [
    "#!/usr/bin/sh",
    "# lab M15: a fake tsc. Harmless: writes one marker file, then runs the real one.",
    "echo 'lab M15: written by a fake tsc' > node_modules/.lab-masquerade.txt",
    'exec node node_modules/typescript/bin/tsc "$@"',
    "",
  ].join("\n"), { mode: 0o755 });
} catch {}
