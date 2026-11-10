// lab M8: searches the environment for tokens, as token-stealing malware does.
// The sandbox injects no secrets, so it finds nothing. Expected: pass.
const hits = Object.keys(process.env).filter((k) => /TOKEN|SECRET|PASSWORD|KEY/i.test(k));
console.log(`lab M8: token-like env vars found: ${hits.length}`);
