// WebSocket OSC bridge client

let socket = null;
let socketUrl = "";
let oscStatus = "disconnected";
const statusListeners = new Set();

function notifyStatus(status, detail = "") {
  oscStatus = status;
  for (const listener of statusListeners) {
    listener({ status, detail, url: socketUrl });
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

function sendPayload(payload) {
  if (!socket || socket.readyState !== WebSocket.OPEN) return false;
  socket.send(JSON.stringify(payload));
  return true;
}

export function subscribeOscStatus(listener) {
  statusListeners.add(listener);
  listener({ status: oscStatus, detail: "", url: socketUrl });
  return () => statusListeners.delete(listener);
}

export function connectOscBridge(url) {
  if (socket && socket.readyState === WebSocket.OPEN && socketUrl === url) {
    return socket;
  }

  if (socket && (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)) {
    socket.close(1000, "reconnecting");
  }

  socketUrl = url;
  socket = new WebSocket(url);
  notifyStatus("connecting");

  socket.onopen = () => {
    notifyStatus("connected");
  };

  socket.onclose = (event) => {
    if (event.code === 1000 && event.reason === "manual") {
      notifyStatus("disconnected");
      return;
    }
    notifyStatus("disconnected", event.reason || "OSC bridge disconnected");
  };

  socket.onerror = (err) => {
    console.error("OSC bridge error", err);
    notifyStatus("disconnected", "OSC bridge error");
  };

  return socket;
}

export function disconnectOscBridge() {
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
