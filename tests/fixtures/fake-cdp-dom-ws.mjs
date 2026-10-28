// Fake CDP websocket for agent-tab upload tests. One connection serves a
// sequence of DOM calls, like Chrome does. A node id is valid only on the
// connection that got it (the session rule), so a client that opens a new
// socket per call fails here, as it would in Chrome.
// Logs "<method> <params-json>" per call to <log-file>.
// Usage: node fake-cdp-dom-ws.mjs <port-file> <log-file>
import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";

const [portFile, logFile] = process.argv.slice(2);

const frame = (text) => {
  const body = Buffer.from(text);
  const head = body.length < 126 ? Buffer.from([0x81, body.length])
    : Buffer.from([0x81, 126, body.length >> 8, body.length & 255]);
  return Buffer.concat([head, body]);
};

// Splits complete masked client frames off the front of buf.
const readFrames = (buf) => {
  const out = [];
  for (;;) {
    if (buf.length < 2) break;
    let len = buf[1] & 0x7f, off = 2;
    if (len === 126) { if (buf.length < 4) break; len = buf.readUInt16BE(2); off = 4; }
    const mask = buf.subarray(off, off + 4); off += 4;
    if (buf.length < off + len) break;
    const body = Buffer.from(buf.subarray(off, off + len));
    for (let i = 0; i < body.length; i++) body[i] ^= mask[i & 3];
    out.push(body.toString("utf8"));
    buf = buf.subarray(off + len);
  }
  return [out, buf];
};

const server = http.createServer();
server.on("upgrade", (req, sock) => {
  const accept = crypto.createHash("sha1")
    .update(req.headers["sec-websocket-key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
  sock.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
    `Sec-WebSocket-Accept: ${accept}\r\n\r\n`);
  let buf = Buffer.alloc(0);
  let gotDoc = false, gotNode = false;
  sock.on("data", (d) => {
    let msgs;
    [msgs, buf] = readFrames(Buffer.concat([buf, d]));
    for (const text of msgs) {
      const m = JSON.parse(text);
      fs.appendFileSync(logFile, `${m.method} ${JSON.stringify(m.params)}\n`);
      let result = {}, error;
      if (m.method === "DOM.getDocument") { gotDoc = true; result = { root: { nodeId: 1 } }; }
      else if (m.method === "DOM.querySelector") {
        if (!gotDoc || m.params.nodeId !== 1) error = { message: "no such node on this session" };
        else if (m.params.selector.includes("missing")) result = { nodeId: 0 };
        else { gotNode = true; result = { nodeId: 9 }; }
      } else if (m.method === "DOM.setFileInputFiles") {
        if (!gotNode || m.params.nodeId !== 9) error = { message: "no such node on this session" };
      }
      sock.write(frame(JSON.stringify(error ? { id: m.id, error } : { id: m.id, result })));
    }
  });
  sock.on("error", () => {});
});
server.listen(0, "127.0.0.1", () => fs.writeFileSync(portFile, String(server.address().port)));
