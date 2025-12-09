import { initMIDI, sendNote, sendCC } from "./midi.js";
import { connectOscBridge, sendOscMessage } from "./oscClient.js";
import mappings from "./mappings.json" assert { type: "json" };

let currentProfileId = null;
let midiAccess = null;
let midiOutput = null;
const padState = new Map(); // id -> boolean

const profileBar = document.getElementById("profile-bar");
const grid = document.getElementById("grid");
const midiSelect = document.getElementById("midi-output-select");
const refreshMidiBtn = document.getElementById("refresh-midi");
const oscToggle = document.getElementById("osc-enabled");

async function main() {
  midiAccess = await initMIDI(populateMidiOutputs);
  buildProfileBar();

  const firstProfile = Object.keys(mappings.profiles)[0];
  if (firstProfile) {
    switchProfile(firstProfile);
  }

  refreshMidiBtn.addEventListener("click", () => {
    if (!midiAccess) return;
    populateMidiOutputs([...midiAccess.outputs.values()]);
  });

  oscToggle.addEventListener("change", (e) => {
    if (e.target.checked) {
      connectOscBridge("ws://localhost:9001");
    }
  });
}

function populateMidiOutputs(outputs) {
  midiSelect.innerHTML = "";
  outputs.forEach((out, idx) => {
    const opt = document.createElement("option");
    opt.value = out.id;
    opt.textContent = out.name || `Output ${idx + 1}`;
    midiSelect.appendChild(opt);
  });

  midiSelect.addEventListener("change", () => {
    const id = midiSelect.value;
    midiOutput =
      [...midiAccess.outputs.values()].find((o) => o.id === id) || null;
  });

  const first = outputs[0];
  if (first) {
    midiSelect.value = first.id;
    midiOutput = first;
  }
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
  grid.innerHTML = "";
  padState.clear();

  profile.pads.forEach((pad) => {
    const div = document.createElement("div");
    div.className = "pad off";
    div.textContent = pad.label || pad.id;
    div.dataset.padId = pad.id;

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
