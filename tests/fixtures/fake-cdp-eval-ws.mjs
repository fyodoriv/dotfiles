// Fake CDP websocket for agent-tab eval tests. It reads one masked client
// frame, which may span many TCP chunks, and answers Runtime.evaluate with
// "chars=<n> sha256=<first 16 hex>" of the expression it received. With
// "close", it drops the connection without an answer.
// Usage: node fake-cdp-eval-ws.mjs <port-file> [close]
import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";

const [portFile, mode] = process.argv.slice(2);

const frame = (text) => {
  const body = Buffer.from(text);
  let head;
  if (body.length < 126) head = Buffer.from([0x81, body.length]);
  else if (body.length < 65536) { head = Buffer.alloc(4); head[0] = 0x81; head[1] = 126; head.writeUInt16BE(body.length, 2); }
  else { head = Buffer.alloc(10); head[0] = 0x81; head[1] = 127; head.writeBigUInt64BE(BigInt(body.length), 2); }
  return Buffer.concat([head, body]);
};

// Returns the unmasked payload of the first complete frame, or null.
const readFrame = (buf) => {
  if (buf.length < 2) return null;
  let len = buf[1] & 0x7f;
  let off = 2;
  if (len === 126) { if (buf.length < 4) return null; len = buf.readUInt16BE(2); off = 4; }
  else if (len === 127) { if (buf.length < 10) return null; len = Number(buf.readBigUInt64BE(2)); off = 10; }
  const mask = buf[1] & 0x80 ? buf.subarray(off, off + 4) : null;
  if (mask) off += 4;
  if (buf.length < off + len) return null;
  const body = Buffer.from(buf.subarray(off, off + len));
  if (mask) for (let i = 0; i < body.length; i++) body[i] ^= mask[i & 3];
  return body.toString("utf8");
};

const server = http.createServer();
server.on("upgrade", (req, sock) => {
  const accept = crypto.createHash("sha1")
    .update(req.headers["sec-websocket-key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
  sock.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
    `Sec-WebSocket-Accept: ${accept}\r\n\r\n`);
  const chunks = [];
  sock.on("data", (d) => {
    chunks.push(d);
    const text = readFrame(Buffer.concat(chunks));
    if (text === null) return;
    chunks.length = 0;
    if (mode === "close") { sock.destroy(); return; }
    const msg = JSON.parse(text);
    const expr = msg.params.expression;
    const sha = crypto.createHash("sha256").update(expr).digest("hex").slice(0, 16);
    sock.write(frame(JSON.stringify({ id: msg.id, result: { result: { type: "string", value: `chars=${expr.length} sha256=${sha}` } } })));
  });
  sock.on("error", () => {});
});
server.listen(0, "127.0.0.1", () => fs.writeFileSync(portFile, String(server.address().port)));
