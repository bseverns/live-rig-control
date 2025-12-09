import WebSocket, { WebSocketServer } from "ws";
import osc from "osc";

const WSS_PORT = process.env.WSS_PORT || 9001;
const OSC_HOST = process.env.OSC_HOST || "127.0.0.1";
const OSC_PORT = Number(process.env.OSC_PORT || 9000);

const wss = new WebSocketServer({ port: WSS_PORT });
const udpPort = new osc.UDPPort({
  localAddress: "0.0.0.0",
  localPort: 0,
  remoteAddress: OSC_HOST,
  remotePort: OSC_PORT
});

udpPort.open();

wss.on("connection", (ws) => {
  ws.on("message", (data) => {
    try {
      const msg = JSON.parse(data.toString());
      if (!msg.address) return;
      udpPort.send(
        {
          address: msg.address,
          args: msg.args || []
        },
        OSC_HOST,
        OSC_PORT
      );
    } catch (e) {
      console.error("Bad OSC payload", e);
    }
  });
});

console.log(`OSC bridge WebSocket listening on ws://localhost:${WSS_PORT}`);
console.log(`Forwarding to OSC ${OSC_HOST}:${OSC_PORT}`);
