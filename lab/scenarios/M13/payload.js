// lab M13: sends one UDP packet to a reserved documentation address
// (TEST-NET-3) without calling connect() first, so the connect hook never
// sees it. The sandbox has no route out, so nothing leaves. Expected: NET-4.
const dgram = require("node:dgram");
const socket = dgram.createSocket("udp4");
socket.send("lab-M13", 53, "203.0.113.10", () => socket.close());
