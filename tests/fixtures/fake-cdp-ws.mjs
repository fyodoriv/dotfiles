// Fake CDP websocket for agent-tab tests: answers every call with one big
// Page.captureScreenshot reply. Usage: node fake-cdp-ws.mjs <port-file> <bytes>
import http from "node:http";
import crypto from "node:crypto";
import fs from "node:fs";

const [portFile, bytes] = process.argv.slice(2);
const png = Buffer.alloc(Number(bytes), 0x41);

const frame = (text) => {
  const body = Buffer.from(text);
  let head;
  if (body.length < 126) head = Buffer.from([0x81, body.length]);
  else if (body.length < 65536) { head = Buffer.alloc(4); head[0] = 0x81; head[1] = 126; head.writeUInt16BE(body.length, 2); }
  else { head = Buffer.alloc(10); head[0] = 0x81; head[1] = 127; head.writeBigUInt64BE(BigInt(body.length), 2); }
  return Buffer.concat([head, body]);
};

const server = http.createServer();
server.on("upgrade", (req, sock) => {
  const accept = crypto.createHash("sha1")
    .update(req.headers["sec-websocket-key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").digest("base64");
  sock.write("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n" +
    `Sec-WebSocket-Accept: ${accept}\r\n\r\n`);
  sock.once("data", () => {
    sock.write(frame(JSON.stringify({ id: 1, result: { data: png.toString("base64") } })));
  });
  sock.on("error", () => {});
});
server.listen(0, "127.0.0.1", () => fs.writeFileSync(portFile, String(server.address().port)));
