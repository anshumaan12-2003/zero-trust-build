const assert = require("node:assert/strict");
const { after, before, test } = require("node:test");
const { createApp, quotes } = require("../dist/app");

let server;
let baseUrl;

before(async () => {
  // Port 0 lets the system pick a free port, so tests never clash.
  server = createApp().listen(0);
  await new Promise((resolve) => server.once("listening", resolve));
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(() => server.close());

test("GET /health reports ok", async () => {
  const response = await fetch(`${baseUrl}/health`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "ok" });
});

test("GET /quote returns one of the known quotes", async () => {
  const response = await fetch(`${baseUrl}/quote`);
  assert.equal(response.status, 200);
  const body = await response.json();
  assert.ok(quotes.includes(body.quote));
});

test("an unknown route returns 404", async () => {
  const response = await fetch(`${baseUrl}/nope`);
  assert.equal(response.status, 404);
});

test("the server does not advertise Express", async () => {
  const response = await fetch(`${baseUrl}/health`);
  assert.equal(response.headers.get("x-powered-by"), null);
});
