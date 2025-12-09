// WebSocket OSC bridge client

let socket = null;

export function connectOscBridge(url) {
  socket = new WebSocket(url);
  socket.onopen = () => console.log("OSC bridge connected");
  socket.onclose = () => console.log("OSC bridge disconnected");
  socket.onerror = (err) => console.error("OSC bridge error", err);
}

export function sendOscMessage(mapping, state) {
  if (!socket || socket.readyState !== WebSocket.OPEN) return;
  if (!mapping.osc) return;

  const payload = {
    address: mapping.osc.address,
    args: mapping.osc.args ?? [],
    state: state // "on" / "off"
  };

  socket.send(JSON.stringify(payload));
}
