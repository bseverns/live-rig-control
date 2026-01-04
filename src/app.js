import { initMIDI, sendNote, sendCC } from "./midi.js";
import { connectOscBridge, sendOscMessage } from "./oscClient.js";

let currentProfileId = null;
let midiAccess = null;
let midiOutput = null;
let cachedMidiOutputs = [];
const padState = new Map(); // id -> boolean
let mappings = null;

const profileBar = document.getElementById("profile-bar");
const grid = document.getElementById("grid");
const midiSelect = document.getElementById("midi-output-select");
const refreshMidiBtn = document.getElementById("refresh-midi");
const oscToggle = document.getElementById("osc-enabled");

async function loadMappings() {
  const res = await fetch("../src/mappings.json", { cache: "no-store" });
  if (!res.ok) throw new Error("Failed to load mappings.json");
  mappings = await res.json();
}

function makeOscUrl() {
  const host = window.location.hostname || "localhost";
  const protocol = window.location.protocol === "https:" ? "wss" : "ws";
  const port = 9001; // default OSC bridge WebSocket port
  return `${protocol}://${host}:${port}`;
}

async function main() {
  await loadMappings();
  midiAccess = await initMIDI(populateMidiOutputs);
  if (!midiAccess) {
    disableMidiUi("WebMIDI unavailable");
  }
  buildProfileBar();

  const firstProfile = Object.keys(mappings.profiles)[0];
  if (firstProfile) {
    switchProfile(firstProfile);
  }

  midiSelect.addEventListener("change", () => {
    const id = midiSelect.value;
    midiOutput = cachedMidiOutputs.find((o) => o.id === id) || null;
  });

  refreshMidiBtn.addEventListener("click", () => {
    if (!midiAccess) return;
    populateMidiOutputs([...midiAccess.outputs.values()]);
  });

  oscToggle.addEventListener("change", (e) => {
    if (e.target.checked) {
      connectOscBridge(makeOscUrl());
    }
  });
}

function disableMidiUi(message) {
  midiOutput = null;
  cachedMidiOutputs = [];
  midiSelect.innerHTML = "";
  const opt = document.createElement("option");
  opt.textContent = message;
  opt.value = "";
  midiSelect.appendChild(opt);
  midiSelect.disabled = true;
  refreshMidiBtn.disabled = true;
}

function populateMidiOutputs(outputs) {
  cachedMidiOutputs = outputs;
  const previousSelection = midiSelect.value || midiOutput?.id;
  midiSelect.innerHTML = "";
  midiSelect.disabled = false;
  refreshMidiBtn.disabled = false;
  outputs.forEach((out, idx) => {
    const opt = document.createElement("option");
    opt.value = out.id;
    opt.textContent = out.name || `Output ${idx + 1}`;
    midiSelect.appendChild(opt);
  });

  const matching = cachedMidiOutputs.find((out) => out.id === previousSelection);
  const first = cachedMidiOutputs[0];
  const nextOutput = matching || first || null;

  midiOutput = nextOutput;
  midiSelect.value = nextOutput?.id ?? "";
}

function buildProfileBar() {
  Object.entries(mappings.profiles).forEach(([id, profile]) => {
    const btn = document.createElement("button");
    btn.textContent = profile.label || id;
    btn.dataset.profileId = id;
    btn.addEventListener("click", () => switchProfile(id));
    profileBar.appendChild(btn);
  });
}

function switchProfile(profileId) {
  currentProfileId = profileId;
  [...profileBar.children].forEach((btn) => {
    btn.classList.toggle("active", btn.dataset.profileId === profileId);
  });

  const profile = mappings.profiles[profileId];
  if (!profile) return;

  const [cols, rows] = profile.gridSize || [8, 8];
  grid.style.gridTemplateColumns = `repeat(${cols}, minmax(0, 1fr))`;
  grid.style.gridTemplateRows = `repeat(${rows}, minmax(64px, 1fr))`;
  grid.innerHTML = "";
  padState.clear();

  profile.pads.forEach((pad, idx) => {
    const div = document.createElement("div");
    div.className = "pad off";
    div.textContent = pad.label || pad.id;
    div.dataset.padId = pad.id;

    const defaultRow = Math.floor(idx / cols);
    const defaultCol = idx % cols;
    const row = Number.isFinite(pad.row) ? pad.row : defaultRow;
    const col = Number.isFinite(pad.col) ? pad.col : defaultCol;
    div.style.gridRow = row + 1;
    div.style.gridColumn = col + 1;

    padState.set(pad.id, false);

    div.addEventListener("click", () => handlePadClick(pad, div));
    grid.appendChild(div);
  });
}

function handlePadClick(pad, element) {
  const isOn = padState.get(pad.id) || false;
  const nextState = pad.toggle ? !isOn : true;

  padState.set(pad.id, nextState);
  element.classList.toggle("on", nextState);
  element.classList.toggle("off", !nextState);

  if (pad.midi) {
    if (pad.midi.type === "note") {
      sendNote(
        midiOutput,
        pad.midi.channel,
        pad.midi.note,
        pad.midi.onVelocity ?? 100,
        pad.midi.offVelocity ?? 0,
        nextState
      );
    } else if (pad.midi.type === "cc") {
      const val = nextState
        ? pad.midi.onValue ?? 127
        : pad.midi.offValue ?? 0;
      sendCC(midiOutput, pad.midi.channel, pad.midi.cc, val);
    }
  }

  if (oscToggle.checked) {
    sendOscMessage(pad, nextState ? "on" : "off");
  }

  if (!pad.toggle) {
    padState.set(pad.id, false);
    element.classList.remove("on");
    element.classList.add("off");
  }
}

main().catch(console.error);
