import { randomUUID } from "crypto";
import { URL } from "url";
import Ajv from "ajv";
import { WebSocketServer } from "ws";
import osc from "osc";

const WSS_PORT = Number(process.env.WSS_PORT || 9001);
const BIND_HOST = process.env.BIND_HOST || "127.0.0.1";
const OSC_HOST = process.env.OSC_HOST || "127.0.0.1";
const OSC_PORT = Number(process.env.OSC_PORT || 9000);
const BRIDGE_TOKEN = process.env.BRIDGE_TOKEN || "";
const MAX_WS_PAYLOAD_BYTES = Number(process.env.MAX_WS_PAYLOAD_BYTES || 4096);
const RATE_WINDOW_MS = Number(process.env.RATE_WINDOW_MS || 5000);
const MAX_MESSAGES_PER_WINDOW = Number(process.env.MAX_MESSAGES_PER_WINDOW || 500);
const DEFAULT_ALLOWED_ORIGINS = [
  "http://localhost:8080",
  "http://127.0.0.1:8080"
];
const ALLOWED_ORIGINS = new Set(
  (process.env.ALLOWED_ORIGINS || DEFAULT_ALLOWED_ORIGINS.join(","))
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean)
);

if (!Number.isInteger(WSS_PORT) || WSS_PORT <= 0) {
  throw new Error(`Invalid WSS_PORT: ${process.env.WSS_PORT}`);
}
if (!Number.isInteger(OSC_PORT) || OSC_PORT <= 0) {
  throw new Error(`Invalid OSC_PORT: ${process.env.OSC_PORT}`);
}
if (!Number.isInteger(MAX_WS_PAYLOAD_BYTES) || MAX_WS_PAYLOAD_BYTES < 512) {
  throw new Error(`Invalid MAX_WS_PAYLOAD_BYTES: ${process.env.MAX_WS_PAYLOAD_BYTES}`);
}

const ajv = new Ajv({ allErrors: true, strict: true });
const validateMessage = ajv.compile({
  type: "object",
  additionalProperties: false,
  required: ["address"],
  properties: {
    address: {
      type: "string",
      minLength: 1,
      maxLength: 128,
      pattern: "^/[A-Za-z0-9_./-]+$"
    },
    args: {
      type: "array",
      maxItems: 32,
      items: {
        anyOf: [
          { type: "string", maxLength: 256 },
          { type: "integer", minimum: -2147483648, maximum: 2147483647 },
          { type: "number" },
          { type: "boolean" }
        ]
      }
    },
    state: {
      type: "string",
      enum: ["on", "off", "value"]
    }
  }
});

const wss = new WebSocketServer({
  host: BIND_HOST,
  port: WSS_PORT,
  maxPayload: MAX_WS_PAYLOAD_BYTES,
  perMessageDeflate: false
});
const udpPort = new osc.UDPPort({
  localAddress: BIND_HOST,
  localPort: 0,
  remoteAddress: OSC_HOST,
  remotePort: OSC_PORT
});

udpPort.open();

function isLoopbackAddress(value) {
  return value === "::1" || value === "127.0.0.1" || value === "::ffff:127.0.0.1";
}

function normalizeRemoteAddress(value) {
  return typeof value === "string" ? value : "";
}

function getRequestUrl(req) {
  return new URL(req.url || "/", `ws://${req.headers.host || `${BIND_HOST}:${WSS_PORT}`}`);
}

function authorizeConnection(req) {
  const remoteAddress = normalizeRemoteAddress(req.socket.remoteAddress);
  const origin = req.headers.origin;
  const isLoopback = isLoopbackAddress(remoteAddress);
  const requestUrl = getRequestUrl(req);

  if (BRIDGE_TOKEN && requestUrl.searchParams.get("token") !== BRIDGE_TOKEN) {
    return { ok: false, reason: "invalid token" };
  }

  if (!origin) {
    return isLoopback
      ? { ok: true, reason: "loopback without origin" }
      : { ok: false, reason: "missing origin" };
  }

  if (ALLOWED_ORIGINS.has(origin)) {
    return { ok: true, reason: "origin allowed" };
  }

  return { ok: false, reason: `origin not allowed: ${origin}` };
}

wss.on("connection", (ws, req) => {
  const auth = authorizeConnection(req);
  if (!auth.ok) {
    ws.close(1008, "Unauthorized");
    console.warn(`Rejected WebSocket connection: ${auth.reason}`);
    return;
  }

  let windowStartedAt = Date.now();
  let messageCount = 0;
  const clientId = randomUUID();

  ws.on("message", (data) => {
    const now = Date.now();
    if (now - windowStartedAt >= RATE_WINDOW_MS) {
      windowStartedAt = now;
      messageCount = 0;
    }
    messageCount += 1;
    if (messageCount > MAX_MESSAGES_PER_WINDOW) {
      ws.close(1008, "Rate limit exceeded");
      console.warn(`Closed WebSocket client ${clientId}: rate limit exceeded`);
      return;
    }

    try {
      const msg = JSON.parse(data.toString());
      if (!validateMessage(msg)) {
        console.warn("Rejected OSC payload", validateMessage.errors);
        return;
      }
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

console.log(`OSC bridge WebSocket listening on ws://${BIND_HOST}:${WSS_PORT}`);
console.log(`Forwarding to OSC ${OSC_HOST}:${OSC_PORT}`);
console.log(`Allowed origins: ${[...ALLOWED_ORIGINS].join(", ") || "(loopback only)"}`);
