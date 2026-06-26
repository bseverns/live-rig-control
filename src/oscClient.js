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

function resolveOscArg(arg, { value = null, state = null } = {}) {
  if (typeof arg !== "string") return arg;
  if (arg === "$value" && Number.isFinite(value)) return value;
  if (arg === "$state" && state) return state;

  let resolved = arg;
  if (Number.isFinite(value)) {
    resolved = resolved.replaceAll("$value", String(value));
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

function enqueuePayload(payload) {
  if (pendingMessages.length >= maxPendingMessages) {
    pendingMessages.shift();
  }
  pendingMessages.push(payload);
  notifyStatus(oscStatus, `OSC queued (${pendingMessages.length})`);
}

function flushPending() {
  if (!socket || socket.readyState !== WebSocket.OPEN) return;
  const queued = pendingMessages.splice(0, pendingMessages.length);
  for (const payload of queued) {
    socket.send(JSON.stringify(payload));
  }
  notifyStatus("connected");
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

function sendPayload(payload) {
  if (!socket || socket.readyState !== WebSocket.OPEN) {
    enqueuePayload(payload);
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
  return sendPayload(payload);
}

export function sendOscValue(mapping, value) {
  if (!mapping?.osc) return false;
  const payload = {
    address: mapping.osc.address,
    args: resolveOscArgs(mapping, { value }),
    state: "value"
  };
  return sendPayload(payload);
}
