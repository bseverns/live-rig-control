// WebSocket OSC bridge client

let socket = null;
let socketUrl = "";
let oscStatus = "disconnected";
let reconnectTimer = null;
let manualDisconnect = false;
const pendingMessages = [];
const statusListeners = new Set();
const maxPendingMessages = 200;
const reconnectDelayMs = 1000;

function notifyStatus(status, detail = "") {
  oscStatus = status;
  for (const listener of statusListeners) {
    listener({ status, detail, url: socketUrl, queuedCount: pendingMessages.length });
  }
}

function queueOptionsForMapping(mapping) {
  const policy = mapping?.queuePolicy ?? (mapping?.ui?.type === "slider" ? "latest" : "ttl");
  const queueKey = mapping?.id || mapping?.osc?.address || "";
  const ttlMs = Number.isFinite(mapping?.queueTtlMs) ? mapping.queueTtlMs : 1000;
  return { policy, queueKey, ttlMs };
}

export function shouldQueueOscPolicy(policy) {
  return policy !== "never" && policy !== "safety";
}

function resolveOscArg(arg, { value = null, state = null } = {}) {
  if (typeof arg !== "string") return arg;
  if (arg === "$value" && Number.isFinite(value)) return value;
  if (arg === "$value01" && Number.isFinite(value)) return value / 127;
  if (arg === "$state" && state) return state;

  let resolved = arg;
  if (Number.isFinite(value)) {
    resolved = resolved
      .replaceAll("$value01", String(value / 127))
      .replaceAll("$value", String(value));
  }
  if (state) {
    resolved = resolved.replaceAll("$state", state);
  }
  return resolved;
}

function resolveOscArgs(mapping, { state = null, value = null } = {}) {
  if (!mapping?.osc) return [];
  const isToggle = typeof mapping.toggle === "boolean"
    ? mapping.toggle
    : mapping.mode === "toggle";

  let source = mapping.osc.args ?? [];
  if (state === "on") {
    source = mapping.osc.onArgs ?? mapping.osc.args ?? [];
  } else if (state === "off") {
    source = mapping.osc.offArgs ?? (isToggle ? [0] : mapping.osc.args ?? []);
  }

  return source.map((arg) => resolveOscArg(arg, { value, state }));
}

function enqueuePayload(payload, options = {}) {
  const policy = options.policy || "ttl";
  if (!shouldQueueOscPolicy(policy)) {
    notifyStatus(oscStatus, "OSC offline; message dropped");
    return false;
  }

  const queueKey = options.queueKey || payload.address;
  const now = Date.now();
  const record = {
    payload,
    policy,
    queueKey,
    expiresAt: policy === "ttl" ? now + (options.ttlMs || 1000) : null
  };

  if (policy === "latest") {
    const existingIndex = pendingMessages.findIndex((entry) => entry.queueKey === queueKey);
    if (existingIndex >= 0) {
      pendingMessages.splice(existingIndex, 1);
    }
  }

  if (pendingMessages.length >= maxPendingMessages) {
    pendingMessages.shift();
  }
  pendingMessages.push(record);
  notifyStatus(oscStatus, `OSC queued (${pendingMessages.length})`);
  return true;
}

function flushPending() {
  if (!socket || socket.readyState !== WebSocket.OPEN) return;
  const now = Date.now();
  const queued = pendingMessages.splice(0, pendingMessages.length);
  let expiredCount = 0;
  for (const record of queued) {
    if (record.expiresAt && record.expiresAt < now) {
      expiredCount += 1;
      continue;
    }
    socket.send(JSON.stringify(record.payload));
  }
  notifyStatus("connected", expiredCount > 0 ? `Expired ${expiredCount} queued OSC message(s)` : "");
}

function clearReconnectTimer() {
  if (!reconnectTimer) return;
  window.clearTimeout(reconnectTimer);
  reconnectTimer = null;
}

function scheduleReconnect(detail = "OSC bridge disconnected; reconnecting") {
  if (manualDisconnect || !socketUrl || reconnectTimer) return;
  notifyStatus("disconnected", detail);
  reconnectTimer = window.setTimeout(() => {
    reconnectTimer = null;
    connectOscBridge(socketUrl);
  }, reconnectDelayMs);
}

function sendPayload(payload, options = {}) {
  if (!socket || socket.readyState !== WebSocket.OPEN) {
    enqueuePayload(payload, options);
    scheduleReconnect();
    return false;
  }
  socket.send(JSON.stringify(payload));
  return true;
}

export function subscribeOscStatus(listener) {
  statusListeners.add(listener);
  listener({ status: oscStatus, detail: "", url: socketUrl, queuedCount: pendingMessages.length });
  return () => statusListeners.delete(listener);
}

export function connectOscBridge(url) {
  manualDisconnect = false;
  clearReconnectTimer();

  if (socket && socket.readyState === WebSocket.OPEN && socketUrl === url) {
    flushPending();
    return socket;
  }

  if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
    socket.close(1000, "reconnecting");
  }

  socketUrl = url;
  socket = new WebSocket(url);
  const activeSocket = socket;
  notifyStatus("connecting");

  socket.onopen = () => {
    if (socket !== activeSocket) return;
    notifyStatus("connected");
    flushPending();
  };

  socket.onclose = (event) => {
    if (socket !== activeSocket) return;
    if (event.code === 1000 && event.reason === "manual") {
      notifyStatus("disconnected");
      return;
    }
    scheduleReconnect(event.reason || "OSC bridge disconnected; reconnecting");
  };

  socket.onerror = (err) => {
    if (socket !== activeSocket) return;
    console.error("OSC bridge error", err);
    scheduleReconnect("OSC bridge error; reconnecting");
  };

  return socket;
}

export function disconnectOscBridge() {
  manualDisconnect = true;
  clearReconnectTimer();
  pendingMessages.length = 0;
  if (!socket) {
    notifyStatus("disconnected");
    return;
  }
  socket.close(1000, "manual");
  socket = null;
  notifyStatus("disconnected");
}

export function getOscState() {
  return oscStatus;
}

export function sendOscMessage(mapping, state) {
  if (!mapping?.osc) return false;
  const payload = {
    address: mapping.osc.address,
    args: resolveOscArgs(mapping, { state }),
    state
  };
  return sendPayload(payload, queueOptionsForMapping(mapping));
}

export function sendOscValue(mapping, value) {
  if (!mapping?.osc) return false;
  const payload = {
    address: mapping.osc.address,
    args: resolveOscArgs(mapping, { value, state: "value" }),
    state: "value"
  };
  return sendPayload(payload, queueOptionsForMapping(mapping));
}
