import { initMIDI, sendNote, sendCC, sendProgramChange, sendRealtime } from "./midi.js";
import { connectOscBridge, sendOscMessage } from "./oscClient.js";

let currentProfileId = null;
let midiAccess = null;
let midiOutput = null;
let cachedMidiOutputs = [];
const padState = new Map(); // id -> { on, lastSent, updatedAt }
const padElements = new Map(); // id -> HTMLElement
const profileControls = new Map(); // profileId -> { velocity, patternBank, velocityOverrides }
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
  initPadState();
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
  padElements.clear();

  profile.pads.forEach((pad, idx) => {
    const ui = getUiConfig(pad);
    const isSlider = ui.type === "slider"
      && (ui.role === "velocity" || ui.role === "velocityOverride" || ui.role === "pattern"
        || pad.midi?.type === "cc" || pad.midi?.type === "program");
    const isPatternBank = ui.role === "patternBank";
    const div = document.createElement("div");
    div.className = isSlider ? "pad slider" : "pad off";
    div.dataset.padId = pad.id;

    const defaultRow = Math.floor(idx / cols);
    const defaultCol = idx % cols;
    const row = Number.isFinite(pad.row) ? pad.row : defaultRow;
    const col = Number.isFinite(pad.col) ? pad.col : defaultCol;
    div.style.gridRow = row + 1;
    div.style.gridColumn = col + 1;

    if (!padState.has(pad.id)) {
      padState.set(pad.id, { on: false, lastSent: null, updatedAt: null });
    }
    padElements.set(pad.id, div);

    const label = document.createElement("div");
    label.className = "pad-label";
    label.textContent = pad.label || pad.id;
    div.appendChild(label);

    if (isSlider) {
      const slider = document.createElement("input");
      slider.type = "range";
      slider.min = String(ui.min);
      slider.max = String(ui.max);
      slider.step = String(ui.step);

      const prevMidiValue = getPadState(pad.id)?.lastSent?.midi?.value;
      const prevUiValue = getPadState(pad.id)?.lastSent?.ui?.value;
      const profileVelocity = getProfileVelocity(currentProfileId);
      let startValue = Number.isFinite(prevMidiValue) ? prevMidiValue : ui.initial;
      if (ui.role === "velocity") {
        startValue = Number.isFinite(prevUiValue) ? prevUiValue : profileVelocity;
      } else if (ui.role === "velocityOverride") {
        const override = getProfileVelocityOverride(currentProfileId, ui.target);
        startValue = Number.isFinite(override) ? override : profileVelocity;
      } else if (ui.role === "pattern") {
        startValue = Number.isFinite(prevUiValue) ? prevUiValue : ui.initial;
      }
      slider.value = String(startValue);

      const valueEl = document.createElement("div");
      valueEl.className = "pad-value";
      valueEl.textContent = String(startValue);

      slider.addEventListener("input", () => {
        const value = Number(slider.value);
        valueEl.textContent = slider.value;
        if (ui.role === "velocity") {
          setProfileVelocity(currentProfileId, value);
          recordSent(pad.id, { ui: { role: "velocity", value } });
          return;
        }
        if (ui.role === "velocityOverride") {
          setProfileVelocityOverride(currentProfileId, ui.target, value);
          recordSent(pad.id, { ui: { role: "velocityOverride", value, target: ui.target } });
          return;
        }
        if (ui.role === "pattern") {
          sendProgramValue(pad, value);
          recordSent(pad.id, { ui: { role: "pattern", value } });
          return;
        }
        if (pad.midi?.type === "program") {
          sendProgramValue(pad, value);
          return;
        }
        sendCcValue(pad, value);
      });

      div.appendChild(slider);
      if (ui.showValue) {
        div.appendChild(valueEl);
      }
    } else if (isPatternBank) {
      const bank = getProfilePatternBank(currentProfileId);
      const isOn = Number.isFinite(ui.bank) && ui.bank === bank;
      div.classList.toggle("on", isOn);
      div.classList.toggle("off", !isOn);
      div.addEventListener("click", () => handlePatternBankClick(pad));
    } else {
      const initialOn = getPadState(pad.id).on;
      div.classList.toggle("on", initialOn);
      div.classList.toggle("off", !initialOn);
      div.addEventListener("click", () => handlePadClick(pad, div));
    }
    grid.appendChild(div);
  });
}

function initPadState() {
  padState.clear();
  for (const profile of Object.values(mappings.profiles ?? {})) {
    for (const pad of profile.pads ?? []) {
      padState.set(pad.id, { on: false, lastSent: null, updatedAt: null });
    }
  }
}

function isTogglePad(pad) {
  if (typeof pad.toggle === "boolean") return pad.toggle;
  if (pad.mode) return pad.mode === "toggle";
  return false;
}

function getGroupInfo(pad) {
  if (!pad.group) return null;
  if (typeof pad.group === "string") {
    return { id: pad.group, exclusive: true };
  }
  return {
    id: pad.group.id,
    exclusive: pad.group.mode === "exclusive" || Boolean(pad.group.exclusive)
  };
}

function getPadState(id) {
  return padState.get(id) ?? { on: false, lastSent: null, updatedAt: null };
}

function setPadState(id, next) {
  padState.set(id, next);
}

function setPadUi(id, on) {
  const el = padElements.get(id);
  if (!el) return;
  if (el.classList.contains("slider")) return;
  el.classList.toggle("on", on);
  el.classList.toggle("off", !on);
}

function recordSent(id, payload) {
  const prev = getPadState(id);
  const lastSent = {
    ...(prev.lastSent ?? {}),
    ...payload
  };
  setPadState(id, {
    on: prev.on,
    lastSent,
    updatedAt: new Date().toISOString()
  });
}

function getUiConfig(pad) {
  const ui = pad.ui ?? {};
  const min = Number.isFinite(ui.min) ? ui.min : 0;
  const max = Number.isFinite(ui.max) ? ui.max : 127;
  const step = Number.isFinite(ui.step) ? ui.step : 1;
  const fallbackInitial = Number.isFinite(pad.midi?.offValue) ? pad.midi.offValue : min;
  const initial = Number.isFinite(ui.initial) ? ui.initial : fallbackInitial;
  const showValue = ui.showValue !== false;
  const role = ui.role ?? null;
  const target = typeof ui.target === "string" ? ui.target : null;
  const bank = Number.isFinite(ui.bank) ? ui.bank : null;
  return {
    type: ui.type ?? "button",
    min,
    max,
    step,
    initial: Math.min(Math.max(initial, min), max),
    showValue,
    role,
    target,
    bank
  };
}

function getProfileControls(profileId) {
  let entry = profileControls.get(profileId);
  if (!entry) {
    entry = { velocity: 100, patternBank: 0, velocityOverrides: new Map() };
    profileControls.set(profileId, entry);
  }
  return entry;
}

function getProfileVelocity(profileId) {
  const entry = getProfileControls(profileId);
  return entry.velocity;
}

function setProfileVelocity(profileId, value) {
  const entry = getProfileControls(profileId);
  entry.velocity = value;
  profileControls.set(profileId, entry);
}

function getProfilePatternBank(profileId) {
  const entry = getProfileControls(profileId);
  return entry.patternBank;
}

function setProfilePatternBank(profileId, value) {
  const entry = getProfileControls(profileId);
  entry.patternBank = value;
  profileControls.set(profileId, entry);
}

function getProfileVelocityOverride(profileId, padId) {
  if (!padId) return null;
  const entry = getProfileControls(profileId);
  return entry.velocityOverrides.get(padId);
}

function setProfileVelocityOverride(profileId, padId, value) {
  if (!padId) return;
  const entry = getProfileControls(profileId);
  entry.velocityOverrides.set(padId, value);
}

function sendCcValue(pad, value) {
  if (!pad.midi || pad.midi.type !== "cc") return;
  const ui = getUiConfig(pad);
  const clamped = Math.min(Math.max(value, ui.min), ui.max);
  sendCC(midiOutput, pad.midi.channel, pad.midi.cc, clamped);
  recordSent(pad.id, { midi: { type: "cc", value: clamped } });
}

function sendProgramValue(pad, value) {
  if (!pad.midi || pad.midi.type !== "program") return;
  const ui = getUiConfig(pad);
  const clamped = Math.min(Math.max(value, ui.min), ui.max);

  let program = clamped;
  let bankMsb = pad.midi.bankMsb;
  let bankLsb = pad.midi.bankLsb;

  if (pad.midi.programBankMode === "electribePattern") {
    const patternBank = ui.role === "pattern" ? getProfilePatternBank(currentProfileId) : null;
    if (Number.isFinite(patternBank)) {
      bankMsb = 0;
      bankLsb = patternBank;
      program = patternBank === 1 ? Math.min(clamped, 121) : clamped;
    } else if (clamped <= 127) {
      bankMsb = 0;
      bankLsb = 0;
      program = clamped;
    } else {
      bankMsb = 0;
      bankLsb = 1;
      program = clamped - 127;
    }
  }

  sendProgramChange(midiOutput, pad.midi.channel, program, bankMsb, bankLsb);
  recordSent(pad.id, { midi: { type: "program", value: clamped } });
}

function handlePatternBankClick(pad) {
  const ui = getUiConfig(pad);
  if (ui.role !== "patternBank") return;
  const bank = Number.isFinite(ui.bank) ? ui.bank : 0;
  setProfilePatternBank(currentProfileId, bank);
  const profile = mappings.profiles[currentProfileId];
  for (const other of profile?.pads ?? []) {
    const otherUi = getUiConfig(other);
    if (otherUi.role !== "patternBank") continue;
    const isOn = Number.isFinite(otherUi.bank) && otherUi.bank === bank;
    setPadState(other.id, {
      on: isOn,
      lastSent: getPadState(other.id).lastSent,
      updatedAt: new Date().toISOString()
    });
    setPadUi(other.id, isOn);
  }
}

function sendOutputs(pad, state, { force = false } = {}) {
  if (pad.midi) {
    if (pad.midi.type === "note") {
      const override = getProfileVelocityOverride(currentProfileId, pad.id);
      const velocity = Number.isFinite(override)
        ? override
        : (Number.isFinite(pad.midi.onVelocity) ? pad.midi.onVelocity : getProfileVelocity(currentProfileId));
      sendNote(
        midiOutput,
        pad.midi.channel,
        pad.midi.note,
        velocity,
        pad.midi.offVelocity ?? 0,
        state === "on"
      );
      recordSent(pad.id, { midi: { type: "note", state } });
    } else if (pad.midi.type === "cc") {
      const val = state === "on"
        ? pad.midi.onValue ?? 127
        : pad.midi.offValue ?? 0;
      sendCC(midiOutput, pad.midi.channel, pad.midi.cc, val);
      recordSent(pad.id, { midi: { type: "cc", state } });
    } else if (pad.midi.type === "program") {
      if (state === "on") {
        if (pad.midi.programBankMode === "electribePattern") {
          const program = pad.midi.program ?? 1;
          const bank = Number.isFinite(getProfilePatternBank(currentProfileId))
            ? getProfilePatternBank(currentProfileId)
            : pad.midi.bankLsb;
          const bankMsb = pad.midi.bankMsb ?? 0;
          const bankLsb = Number.isFinite(bank) ? bank : pad.midi.bankLsb;
          const safeProgram = bankLsb === 1 ? Math.min(program, 121) : program;
          sendProgramChange(midiOutput, pad.midi.channel, safeProgram, bankMsb, bankLsb);
        } else {
          sendProgramChange(
            midiOutput,
            pad.midi.channel,
            pad.midi.program,
            pad.midi.bankMsb,
            pad.midi.bankLsb
          );
        }
        recordSent(pad.id, { midi: { type: "program", state } });
      }
    } else if (pad.midi.type === "realtime") {
      if (state === "on") {
        sendRealtime(midiOutput, pad.midi.realtime);
        recordSent(pad.id, { midi: { type: "realtime", state } });
      }
    }
  }

  if ((oscToggle.checked || force) && pad.osc) {
    sendOscMessage(pad, state);
    recordSent(pad.id, { osc: { address: pad.osc.address, state } });
  }
}

function enforceExclusiveGroup(pad, profile) {
  const group = getGroupInfo(pad);
  if (!group?.exclusive) return;
  for (const other of profile.pads) {
    if (other.id === pad.id) continue;
    const otherGroup = getGroupInfo(other);
    if (!otherGroup || otherGroup.id !== group.id) continue;
    if (!isTogglePad(other)) continue;
    setPadState(other.id, { on: false, lastSent: getPadState(other.id).lastSent, updatedAt: new Date().toISOString() });
    setPadUi(other.id, false);
    sendOutputs(other, "off");
  }
}

function handlePadClick(pad, element) {
  const current = getPadState(pad.id).on;
  const togglePad = isTogglePad(pad);
  const nextOn = togglePad ? !current : true;
  const state = nextOn ? "on" : "off";

  const profile = mappings.profiles[currentProfileId];
  if (nextOn && profile) {
    enforceExclusiveGroup(pad, profile);
  }

  setPadState(pad.id, {
    on: nextOn,
    lastSent: getPadState(pad.id).lastSent,
    updatedAt: new Date().toISOString()
  });
  setPadUi(pad.id, nextOn);
  sendOutputs(pad, state);

  if (!togglePad) {
    setPadState(pad.id, {
      on: false,
      lastSent: getPadState(pad.id).lastSent,
      updatedAt: new Date().toISOString()
    });
    setPadUi(pad.id, false);
  }
}

function dumpState() {
  const snapshot = {};
  for (const [id, entry] of padState.entries()) {
    snapshot[id] = entry;
  }
  console.log("Pad state snapshot:", snapshot);
  return snapshot;
}

function safeBlackout() {
  const allPads = [];
  for (const profile of Object.values(mappings.profiles ?? {})) {
    for (const pad of profile.pads ?? []) {
      allPads.push(pad);
    }
  }

  const blackoutPads = allPads.filter((pad) => pad.osc?.address === "/nw_wrld/feed/blackout" || pad.id === "nw_feed_blackout");
  const overlayOrFxPads = allPads.filter((pad) =>
    pad.id?.startsWith("nw_overlay_") ||
    pad.id?.startsWith("nw_fx_") ||
    pad.osc?.address?.includes("/overlay/") ||
    pad.osc?.address?.includes("/fx/")
  );

  for (const pad of overlayOrFxPads) {
    setPadState(pad.id, { on: false, lastSent: getPadState(pad.id).lastSent, updatedAt: new Date().toISOString() });
    setPadUi(pad.id, false);
    sendOutputs(pad, "off", { force: true });
  }

  for (const pad of blackoutPads) {
    setPadState(pad.id, { on: true, lastSent: getPadState(pad.id).lastSent, updatedAt: new Date().toISOString() });
    setPadUi(pad.id, true);
    sendOutputs(pad, "on", { force: true });
  }
}

window.dumpState = dumpState;
window.safeBlackout = safeBlackout;

main().catch(console.error);
