import { initMIDI, sendNote, sendCC, sendProgramChange, sendRealtime } from "./midi.js";
import {
  connectOscBridge,
  disconnectOscBridge,
  sendOscMessage,
  sendOscValue,
  subscribeOscStatus
} from "./oscClient.js";

const SECTION_ORDER = ["show", "sound", "video", "setup"];
const SECTION_TITLES = {
  show: "Show",
  sound: "Sound",
  video: "Video",
  setup: "Setup"
};
const STORAGE_KEYS = {
  selectedProfileId: "selected_profile_id",
  selectedSection: "selected_section",
  selectedMidiOutputId: "selected_midi_output_id",
  oscEnabled: "osc_enabled",
  oscHost: "osc_host",
  logsEnabled: "log_enabled"
};
const SLIDER_SEND_INTERVAL_MS = 20;
const MAX_LOG_ENTRIES = 200;

let mappings = null;
let profiles = [];
let profileIssues = {};
let currentProfileId = window.localStorage.getItem(STORAGE_KEYS.selectedProfileId);
let selectedSection = window.localStorage.getItem(STORAGE_KEYS.selectedSection);
let selectedMidiOutputId = window.localStorage.getItem(STORAGE_KEYS.selectedMidiOutputId);
let midiAccess = null;
let midiOutput = null;
let cachedMidiOutputs = [];
let oscEnabled = window.localStorage.getItem(STORAGE_KEYS.oscEnabled) === "true";
let oscHost = window.localStorage.getItem(STORAGE_KEYS.oscHost) ?? "";
let oscHostError = null;
let oscHostHint = "";
let oscStatus = "disconnected";
let oscStatusDetail = "";
let oscQueuedCount = 0;
let logsEnabled = window.localStorage.getItem(STORAGE_KEYS.logsEnabled) !== "false";
let showingConnections = true;
let showingLogs = false;

const logs = [];
const padState = new Map();
const padElements = new Map();
const profileControls = new Map();
const sliderValues = new Map();
const lastSliderSend = new Map();
const pendingSliderValues = new Map();
const pendingSliderTimers = new Map();

const selectedProfileNameEl = document.getElementById("selected-profile-name");
const midiPillDetailEl = document.getElementById("midi-pill-detail");
const oscPillDotEl = document.getElementById("osc-pill-dot");
const oscPillDetailEl = document.getElementById("osc-pill-detail");
const appReadinessEl = document.getElementById("app-readiness");
const connectionsToggleBtn = document.getElementById("connections-toggle");
const logsToggleBtn = document.getElementById("logs-toggle");
const safeBlackoutBtn = document.getElementById("safe-blackout");
const connectionsPanel = document.getElementById("connections-panel");
const logsPanel = document.getElementById("logs-panel");
const sectionBar = document.getElementById("section-bar");
const profileBar = document.getElementById("profile-bar");
const profileWarnings = document.getElementById("profile-warnings");
const surfaceTitle = document.getElementById("surface-title");
const surfaceMeta = document.getElementById("surface-meta");
const surface = document.getElementById("surface");
const emptyState = document.getElementById("empty-state");
const midiSelect = document.getElementById("midi-output-select");
const refreshMidiBtn = document.getElementById("refresh-midi");
const midiSelectedLabel = document.getElementById("midi-selected-label");
const oscHostInput = document.getElementById("osc-host");
const oscToggle = document.getElementById("osc-enabled");
const oscStatusDot = document.getElementById("osc-status-dot");
const oscStatusText = document.getElementById("osc-status-text");
const oscReconnectBtn = document.getElementById("osc-reconnect");
const oscHostErrorEl = document.getElementById("osc-host-error");
const oscHostHintEl = document.getElementById("osc-host-hint");
const scanQrBtn = document.getElementById("scan-qr");
const qrScanner = document.getElementById("qr-scanner");
const qrCloseBtn = document.getElementById("qr-close");
const qrVideo = document.getElementById("qr-video");
const qrStatus = document.getElementById("qr-status");
const logEnabledToggle = document.getElementById("log-enabled");
const clearLogsBtn = document.getElementById("clear-logs");
const logEntriesEl = document.getElementById("log-entries");

let qrStream = null;
let qrDetector = null;
let qrScanFrame = null;
let safeBlackoutArmedUntil = 0;
let safeBlackoutArmTimer = null;

async function loadMappings() {
  const response = await fetch("../src/mappings.json", { cache: "no-store" });
  if (!response.ok) {
    throw new Error("Failed to load mappings.json");
  }
  mappings = await response.json();
  profiles = normalizeProfiles(mappings);
  profileIssues = validateProfiles(profiles);
}

function normalizeProfiles(mappingDoc) {
  return Object.entries(mappingDoc?.profiles ?? {})
    .map(([id, profile]) => ({
      id,
      label: profile.label,
      section: profile.section,
      order: profile.order,
      layout: normalizeLayout(profile.layout),
      gridSize: profile.gridSize,
      pads: profile.pads ?? []
    }))
    .sort((left, right) => {
      const leftRank = sectionRank(profileSection(left));
      const rightRank = sectionRank(profileSection(right));
      if (leftRank !== rightRank) return leftRank - rightRank;

      const leftOrder = Number.isFinite(left.order) ? left.order : 999;
      const rightOrder = Number.isFinite(right.order) ? right.order : 999;
      if (leftOrder !== rightOrder) return leftOrder - rightOrder;

      return profileName(left).localeCompare(profileName(right));
    });
}

function normalizeLayout(layout) {
  const allowedKinds = new Set(["performanceDeck", "parameterBoard", "mappedGrid"]);
  const kind = allowedKinds.has(layout?.kind) ? layout.kind : "mappedGrid";
  const minCardWidth = Number.isFinite(layout?.minCardWidth) ? layout.minCardWidth : 180;
  return {
    kind,
    minCardWidth,
    riskDisplay: layout?.riskDisplay !== false
  };
}

function sectionRank(section) {
  const index = SECTION_ORDER.indexOf(section);
  return index >= 0 ? index : 0;
}

function profileSection(profile) {
  const section = typeof profile?.section === "string" ? profile.section.toLowerCase() : "";
  return SECTION_ORDER.includes(section) ? section : "show";
}

function profileName(profile) {
  return profile?.label || profile?.id || "Unknown";
}

function currentProfile() {
  return profiles.find((profile) => profile.id === currentProfileId) ?? null;
}

function currentSectionProfiles() {
  const section = currentSection();
  return profiles.filter((profile) => profileSection(profile) === section);
}

function availableSections() {
  const used = new Set(profiles.map(profileSection));
  return SECTION_ORDER.filter((section) => used.has(section));
}

function currentSection() {
  const selected = typeof selectedSection === "string" ? selectedSection : "";
  if (availableSections().includes(selected)) return selected;
  if (currentProfile()) return profileSection(currentProfile());
  return availableSections()[0] ?? "show";
}

function profileLayoutKind(profile) {
  return normalizeLayout(profile?.layout).kind;
}

function sortedPadsForDisplay(profile) {
  return [...(profile?.pads ?? [])].sort((left, right) => {
    const leftRow = Number.isFinite(left.row) ? left.row : Number.MAX_SAFE_INTEGER;
    const rightRow = Number.isFinite(right.row) ? right.row : Number.MAX_SAFE_INTEGER;
    if (leftRow !== rightRow) return leftRow - rightRow;

    const leftCol = Number.isFinite(left.col) ? left.col : Number.MAX_SAFE_INTEGER;
    const rightCol = Number.isFinite(right.col) ? right.col : Number.MAX_SAFE_INTEGER;
    if (leftCol !== rightCol) return leftCol - rightCol;

    return left.id.localeCompare(right.id);
  });
}

function validateProfiles(profileList) {
  const issues = {};
  profileList.forEach((profile) => {
    const messages = [];
    const cols = Math.max(profile.gridSize?.[0] ?? 8, 1);
    const rows = Math.max(profile.gridSize?.[1] ?? 8, 1);
    if (!profile.gridSize) {
      messages.push("Missing gridSize; defaulting to 8x8.");
    }

    const occupied = new Set();
    profile.pads.forEach((pad, index) => {
      const defaultRow = Math.floor(index / cols);
      const defaultCol = index % cols;
      const row = Number.isFinite(pad.row) ? pad.row : defaultRow;
      const col = Number.isFinite(pad.col) ? pad.col : defaultCol;
      if (row < 0 || row >= rows || col < 0 || col >= cols) {
        messages.push(`Pad ${pad.id} out of bounds (${row},${col}) for ${cols}x${rows}.`);
        return;
      }

      const key = `${row},${col}`;
      if (occupied.has(key)) {
        messages.push(`Pad collision at (${row},${col}).`);
      } else {
        occupied.add(key);
      }
    });

    issues[profile.id] = messages;
    if (messages.length > 0) {
      addLog(`Profile ${profile.id} has ${messages.length} issue(s)`);
    }
  });
  return issues;
}

function initPadState() {
  padState.clear();
  (profiles ?? []).forEach((profile) => {
    (profile.pads ?? []).forEach((pad) => {
      padState.set(pad.id, { on: false, lastSent: null, updatedAt: null });
    });
  });
}

function bindUi() {
  connectionsToggleBtn.addEventListener("click", () => {
    showingConnections = true;
    renderPanels();
  });

  logsToggleBtn.addEventListener("click", () => {
    showingLogs = !showingLogs;
    renderPanels();
  });

  safeBlackoutBtn.addEventListener("click", handleSafeBlackoutClick);

  midiSelect.addEventListener("change", () => {
    const nextId = midiSelect.value;
    midiOutput = cachedMidiOutputs.find((output) => output.id === nextId) ?? null;
    selectedMidiOutputId = midiOutput?.id ?? "";
    window.localStorage.setItem(STORAGE_KEYS.selectedMidiOutputId, selectedMidiOutputId);
    addLog(midiOutput ? `MIDI output selected: ${midiOutput.name}` : "MIDI output cleared");
    renderStatus();
    renderConnections();
  });

  refreshMidiBtn.addEventListener("click", () => {
    if (!midiAccess) return;
    populateMidiOutputs([...midiAccess.outputs.values()]);
    addLog("MIDI outputs refreshed");
  });

  oscHostInput.addEventListener("change", handleOscHostCommit);
  oscHostInput.addEventListener("blur", handleOscHostCommit);
  oscHostInput.addEventListener("keydown", (event) => {
    if (event.key === "Enter") {
      event.preventDefault();
      handleOscHostCommit();
    }
  });

  oscToggle.addEventListener("change", () => {
    oscEnabled = oscToggle.checked;
    window.localStorage.setItem(STORAGE_KEYS.oscEnabled, String(oscEnabled));
    if (oscEnabled) {
      addLog("OSC enabled");
      connectCurrentOsc();
    } else {
      addLog("OSC disabled");
      disconnectOscBridge();
      renderStatus();
      renderConnections();
    }
  });

  oscReconnectBtn.addEventListener("click", () => {
    if (!oscEnabled) {
      oscEnabled = true;
      oscToggle.checked = true;
      window.localStorage.setItem(STORAGE_KEYS.oscEnabled, "true");
    }
    connectCurrentOsc();
  });

  scanQrBtn.addEventListener("click", startQrScanner);
  qrCloseBtn.addEventListener("click", stopQrScanner);
  qrScanner.addEventListener("click", (event) => {
    if (event.target === qrScanner) {
      stopQrScanner();
    }
  });

  logEnabledToggle.addEventListener("change", () => {
    logsEnabled = logEnabledToggle.checked;
    window.localStorage.setItem(STORAGE_KEYS.logsEnabled, String(logsEnabled));
    renderLogs();
  });

  clearLogsBtn.addEventListener("click", () => {
    logs.length = 0;
    renderLogs();
  });

  window.addEventListener("resize", () => {
    const profile = currentProfile();
    if (profile && profileLayoutKind(profile) === "mappedGrid") {
      renderSurface(profile);
    }
  });

  window.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && !qrScanner.classList.contains("hidden")) {
      stopQrScanner();
    }
  });
}

function handleSafeBlackoutClick() {
  const now = Date.now();
  if (safeBlackoutArmedUntil > now) {
    disarmSafeBlackout();
    safeBlackout();
    addLog("Safe blackout executed");
    return;
  }

  safeBlackoutArmedUntil = now + 4000;
  safeBlackoutBtn.classList.add("armed");
  safeBlackoutBtn.textContent = "Confirm Safe Blackout";
  if (safeBlackoutArmTimer) {
    window.clearTimeout(safeBlackoutArmTimer);
  }
  safeBlackoutArmTimer = window.setTimeout(disarmSafeBlackout, 4000);
}

function disarmSafeBlackout() {
  safeBlackoutArmedUntil = 0;
  if (safeBlackoutArmTimer) {
    window.clearTimeout(safeBlackoutArmTimer);
    safeBlackoutArmTimer = null;
  }
  safeBlackoutBtn.classList.remove("armed");
  safeBlackoutBtn.textContent = "Arm Safe Blackout";
}

function renderPanels() {
  connectionsPanel.classList.toggle("hidden", !showingConnections);
  logsPanel.classList.toggle("hidden", !showingLogs);
  connectionsToggleBtn.classList.toggle("active", showingConnections);
  logsToggleBtn.classList.toggle("active", showingLogs);
}

function renderAll() {
  renderPanels();
  renderStatus();
  renderSections();
  renderProfiles();
  renderWarnings();
  renderConnections();
  renderLogs();

  const profile = currentProfile();
  if (!profile) {
    surface.innerHTML = "";
    surface.className = "surface";
    surfaceTitle.textContent = "No profile loaded";
    surfaceMeta.textContent = "";
    emptyState.classList.remove("hidden");
    return;
  }

  emptyState.classList.add("hidden");
  renderSurface(profile);
}

function renderStatus() {
  const profile = currentProfile();
  selectedProfileNameEl.textContent = profile ? profileName(profile) : "No profile selected";

  midiPillDetailEl.textContent = midiOutput?.name || "Not Connected";

  const oscLabel = oscEnabled
    ? (oscStatus === "connected"
      ? (oscQueuedCount > 0 ? `Connected (${oscQueuedCount} queued)` : "Connected")
      : oscStatus === "connecting"
        ? "Connecting"
        : (oscQueuedCount > 0 ? `Disconnected (${oscQueuedCount} queued)` : "Disconnected"))
    : "Disabled";
  oscPillDetailEl.textContent = oscLabel;

  oscPillDotEl.className = `status-dot osc ${oscEnabled ? oscStatus : "disconnected"}`;
  oscStatusDot.className = `status-dot osc ${oscEnabled ? oscStatus : "disconnected"}`;

  if (oscEnabled || cachedMidiOutputs.length > 0) {
    appReadinessEl.textContent = "Control surface ready";
  } else {
    appReadinessEl.textContent = "Set up MIDI or OSC, then select a profile.";
  }
}

function renderSections() {
  const section = currentSection();
  selectedSection = section;
  window.localStorage.setItem(STORAGE_KEYS.selectedSection, section);
  sectionBar.innerHTML = "";

  availableSections().forEach((entry) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `section-chip${entry === section ? " active" : ""}`;
    button.textContent = SECTION_TITLES[entry] ?? entry;
    button.addEventListener("click", () => selectSection(entry));
    sectionBar.appendChild(button);
  });
}

function renderProfiles() {
  profileBar.innerHTML = "";
  currentSectionProfiles().forEach((profile) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `profile-chip${profile.id === currentProfileId ? " active" : ""}`;
    button.dataset.profileId = profile.id;

    const label = document.createElement("span");
    label.textContent = profileName(profile);
    button.appendChild(label);

    const issues = profileIssues[profile.id] ?? [];
    if (issues.length > 0) {
      const badge = document.createElement("span");
      badge.className = "warning-badge";
      badge.textContent = "!";
      button.appendChild(badge);
    }

    button.addEventListener("click", () => switchProfile(profile.id));
    profileBar.appendChild(button);
  });
}

function renderWarnings() {
  const issues = currentProfileId ? (profileIssues[currentProfileId] ?? []) : [];
  if (issues.length === 0) {
    profileWarnings.classList.add("hidden");
    profileWarnings.innerHTML = "";
    return;
  }

  profileWarnings.classList.remove("hidden");
  profileWarnings.innerHTML = `
    <h3>Profile warnings</h3>
    <ul>${issues.slice(0, 3).map((issue) => `<li>${escapeHtml(issue)}</li>`).join("")}</ul>
  `;
}

function renderConnections() {
  oscHostInput.value = oscHost;
  oscToggle.checked = oscEnabled;

  if (!midiAccess) {
    ensureMidiPlaceholder("WebMIDI unavailable");
    midiSelectedLabel.textContent = "WebMIDI unavailable";
    refreshMidiBtn.disabled = true;
    midiSelect.disabled = true;
  } else if (cachedMidiOutputs.length === 0) {
    ensureMidiPlaceholder("No MIDI outputs");
    midiSelectedLabel.textContent = "No output selected";
    refreshMidiBtn.disabled = false;
    midiSelect.disabled = false;
  } else if (midiOutput) {
    midiSelectedLabel.textContent = `Selected: ${midiOutput.name}`;
    refreshMidiBtn.disabled = false;
    midiSelect.disabled = false;
  } else {
    midiSelectedLabel.textContent = "No output selected";
    refreshMidiBtn.disabled = false;
    midiSelect.disabled = false;
  }

  oscHostErrorEl.textContent = oscHostError || "";
  oscHostErrorEl.classList.toggle("hidden", !oscHostError);

  oscHostHintEl.textContent = oscHostHint || "";
  oscHostHintEl.classList.toggle("hidden", !oscHostHint);

  if (!oscEnabled) {
    oscStatusText.textContent = "OSC disabled";
  } else if (oscStatus === "connecting") {
    oscStatusText.textContent = "OSC connecting...";
  } else if (oscStatus === "connected") {
    oscStatusText.textContent = oscQueuedCount > 0
      ? `OSC connected; ${oscQueuedCount} queued`
      : "OSC connected";
  } else {
    oscStatusText.textContent = oscQueuedCount > 0
      ? `${oscStatusDetail || "OSC disconnected"}; ${oscQueuedCount} queued`
      : (oscStatusDetail || "OSC disconnected");
  }

  oscReconnectBtn.disabled = Boolean(oscHostError) || oscStatus === "connecting";
}

function renderLogs() {
  logEnabledToggle.checked = logsEnabled;
  if (!logsEnabled) {
    logEntriesEl.innerHTML = '<div class="log-entry">Debug logging disabled</div>';
    return;
  }

  if (logs.length === 0) {
    logEntriesEl.innerHTML = '<div class="log-entry">No log entries yet</div>';
    return;
  }

  logEntriesEl.innerHTML = logs
    .map((entry) => `<div class="log-entry">${escapeHtml(entry.timestamp)}  ${escapeHtml(entry.message)}</div>`)
    .join("");
  logEntriesEl.scrollTop = logEntriesEl.scrollHeight;
}

function renderSurface(profile) {
  surface.innerHTML = "";
  padElements.clear();
  surfaceTitle.textContent = profileName(profile);
  surfaceMeta.textContent = `${profile.pads.length} controls • ${SECTION_TITLES[profileSection(profile)] ?? "Show"}`;

  const layout = profileLayoutKind(profile);
  if (layout === "performanceDeck") {
    surface.className = "surface performance-deck";
    surface.style.removeProperty("--parameter-card-min");
    const track = document.createElement("div");
    track.className = "performance-deck-track";
    sortedPadsForDisplay(profile).forEach((pad) => {
      track.appendChild(createPadElement(pad));
    });
    surface.appendChild(track);
    return;
  }

  if (layout === "parameterBoard") {
    surface.className = "surface parameter-board";
    surface.style.setProperty("--parameter-card-min", `${normalizeLayout(profile.layout).minCardWidth}px`);
    sortedPadsForDisplay(profile).forEach((pad) => {
      surface.appendChild(createPadElement(pad));
    });
    return;
  }

  surface.style.removeProperty("--parameter-card-min");
  surface.className = "surface mapped-grid";
  const cols = Math.max(profile.gridSize?.[0] ?? 8, 1);
  const rows = Math.max(profile.gridSize?.[1] ?? 8, 1);
  const spacing = 10;
  const visibleCols = Math.min(cols, 8);
  const availableWidth = Math.max(surface.clientWidth || window.innerWidth - 80, 360);
  const cellSize = Math.max(92, Math.floor((availableWidth - spacing * (visibleCols - 1)) / visibleCols));

  const grid = document.createElement("div");
  grid.className = "mapped-grid-inner";
  grid.style.gridTemplateColumns = `repeat(${cols}, ${cellSize}px)`;
  grid.style.gridAutoRows = `${cellSize}px`;

  buildPadMatrix(profile.pads, rows, cols).forEach((row) => {
    row.forEach((pad) => {
      if (pad) {
        const element = createPadElement(pad);
        if (pad.ui?.type === "slider") {
          element.style.minHeight = `${Math.max(104, Math.floor(cellSize * 1.15))}px`;
        } else {
          element.style.minHeight = `${cellSize}px`;
        }
        grid.appendChild(element);
      } else {
        const empty = document.createElement("div");
        empty.className = "grid-slot-empty";
        empty.style.minHeight = `${cellSize}px`;
        grid.appendChild(empty);
      }
    });
  });

  surface.appendChild(grid);
}

function createPadElement(pad) {
  if (pad.ui?.type === "slider") {
    return createSliderPad(pad);
  }
  return createButtonPad(pad);
}

function createButtonPad(pad) {
  const element = document.createElement("button");
  const isOn = getPadState(pad.id).on;
  element.type = "button";
  element.className = `pad-card button-pad risk-${padRisk(pad)} ${isOn ? "on" : "off"}`;
  element.dataset.padId = pad.id;
  element.innerHTML = `
    <span class="risk-mark">${escapeHtml(padRiskLabel(pad))}</span>
    <span class="pad-label">${escapeHtml(pad.label || pad.id)}</span>
  `;
  padElements.set(pad.id, element);

  if (pad.ui?.role === "patternBank") {
    element.addEventListener("click", () => handlePatternBankClick(pad));
    return element;
  }

  if (isTogglePad(pad)) {
    element.addEventListener("click", () => handleTogglePad(pad));
    return element;
  }

  let pressed = false;
  const press = () => {
    if (pressed) return;
    pressed = true;
    element.classList.add("pressed");
    handleMomentaryPadPress(pad);
  };
  const release = () => {
    if (!pressed) return;
    pressed = false;
    element.classList.remove("pressed");
    handleMomentaryPadRelease(pad);
  };

  element.addEventListener("pointerdown", (event) => {
    event.preventDefault();
    element.setPointerCapture?.(event.pointerId);
    press();
  });
  element.addEventListener("pointerup", release);
  element.addEventListener("pointercancel", release);
  element.addEventListener("pointerleave", release);
  return element;
}

function createSliderPad(pad) {
  const ui = getUiConfig(pad);
  const value = sliderValueForPad(pad);
  const element = document.createElement("div");
  element.className = `pad-card slider-pad risk-${padRisk(pad)}`;
  element.dataset.padId = pad.id;

  const label = document.createElement("div");
  label.className = "pad-label";
  label.innerHTML = `
    <span>${escapeHtml(pad.label || pad.id)}</span>
    <span class="risk-mark">${escapeHtml(padRiskLabel(pad))}</span>
  `;

  const slider = document.createElement("input");
  slider.type = "range";
  slider.min = String(ui.min);
  slider.max = String(ui.max);
  slider.step = String(ui.step);
  slider.value = String(value);

  const valueEl = document.createElement("div");
  valueEl.className = "pad-value";
  valueEl.textContent = String(value);
  valueEl.classList.toggle("hidden", !ui.showValue);

  slider.addEventListener("input", () => {
    const nextValue = Number(slider.value);
    valueEl.textContent = String(nextValue);
    handleSliderChange(pad, nextValue);
  });

  element.append(label, slider, valueEl);
  return element;
}

function padRisk(pad) {
  return ["low", "medium", "high", "critical"].includes(pad?.risk) ? pad.risk : "medium";
}

function padRiskLabel(pad) {
  return {
    low: "LOW",
    medium: "MED",
    high: "HIGH",
    critical: "CRIT"
  }[padRisk(pad)];
}

function selectSection(section) {
  selectedSection = section;
  window.localStorage.setItem(STORAGE_KEYS.selectedSection, section);
  const current = currentProfile();
  if (!current || profileSection(current) !== section) {
    const first = profiles.find((profile) => profileSection(profile) === section);
    if (first) {
      switchProfile(first.id);
      return;
    }
  }
  renderAll();
}

function switchProfile(profileId) {
  const next = profiles.find((profile) => profile.id === profileId);
  if (!next) return;
  currentProfileId = profileId;
  selectedSection = profileSection(next);
  window.localStorage.setItem(STORAGE_KEYS.selectedProfileId, profileId);
  window.localStorage.setItem(STORAGE_KEYS.selectedSection, selectedSection);
  syncPatternBankState();
  renderAll();
}

function chooseInitialProfile() {
  const preferred = profiles.find((profile) => profile.id === currentProfileId);
  const section = availableSections().includes(selectedSection) ? selectedSection : null;
  const firstInSection = section
    ? profiles.find((profile) => profileSection(profile) === section)
    : null;
  const firstProfile = preferred || firstInSection || profiles[0] || null;

  if (!firstProfile) {
    currentProfileId = null;
    selectedSection = null;
    return;
  }

  currentProfileId = firstProfile.id;
  selectedSection = profileSection(firstProfile);
  window.localStorage.setItem(STORAGE_KEYS.selectedProfileId, currentProfileId);
  window.localStorage.setItem(STORAGE_KEYS.selectedSection, selectedSection);
  syncPatternBankState();
}

function populateMidiOutputs(outputs) {
  cachedMidiOutputs = outputs;
  const previous = selectedMidiOutputId || midiOutput?.id || midiSelect.value;
  midiSelect.innerHTML = "";

  if (outputs.length === 0) {
    const option = document.createElement("option");
    option.value = "";
    option.textContent = "No MIDI outputs";
    midiSelect.appendChild(option);
    midiOutput = null;
    selectedMidiOutputId = "";
    renderStatus();
    renderConnections();
    return;
  }

  outputs.forEach((output, index) => {
    const option = document.createElement("option");
    option.value = output.id;
    option.textContent = output.name || `Output ${index + 1}`;
    midiSelect.appendChild(option);
  });

  midiOutput = outputs.find((output) => output.id === previous) ?? outputs[0] ?? null;
  selectedMidiOutputId = midiOutput?.id ?? "";
  midiSelect.value = selectedMidiOutputId;
  window.localStorage.setItem(STORAGE_KEYS.selectedMidiOutputId, selectedMidiOutputId);
  renderStatus();
  renderConnections();
}

function handleOscHostCommit() {
  const raw = oscHostInput.value.trim();
  const sanitized = sanitizeOscHost(raw);
  oscHost = sanitized;
  oscHostHint = sanitized !== raw && sanitized !== "" ? `Host normalized to ${sanitized}` : "";
  oscHostError = validateOscHost(sanitized);
  window.localStorage.setItem(STORAGE_KEYS.oscHost, oscHost);

  if (oscHostError) {
    addLog("OSC host invalid");
    renderConnections();
    return;
  }

  addLog(`OSC host set to ${oscHost || "localhost"}`);
  renderConnections();
  if (oscEnabled) {
    connectCurrentOsc();
  }
}

function validateOscHost(host) {
  if (!host) return null;
  if (/\s/.test(host)) {
    return "OSC endpoint cannot contain spaces.";
  }

  if (host.includes("://")) {
    let parsed;
    try {
      parsed = new URL(host);
    } catch {
      return "Use a plain host or ws:// / wss:// endpoint.";
    }

    const scheme = parsed.protocol.replace(":", "").toLowerCase();
    if (!["ws", "wss"].includes(scheme)) {
      return "Web app OSC endpoint must use ws:// or wss://.";
    }
    if (!parsed.hostname) {
      return "OSC endpoint must include a host.";
    }
    if (parsed.pathname && parsed.pathname !== "/") {
      return "OSC endpoint cannot include a path.";
    }
    return null;
  }

  if (host.includes("/")) {
    return "Host cannot include paths.";
  }
  return null;
}

function sanitizeOscHost(host) {
  const trimmed = host.trim();
  if (!trimmed) return "";
  if (!trimmed.includes("://")) {
    return trimmed.replace(/\/+$/, "");
  }

  try {
    const parsed = new URL(trimmed);
    if (!parsed.hostname) return trimmed;
    const scheme = parsed.protocol.replace(":", "").toLowerCase();
    const port = parsed.port ? `:${parsed.port}` : "";
    return `${scheme}://${parsed.hostname}${port}`;
  } catch {
    return trimmed;
  }
}

function makeOscUrl(host) {
  if (host && host.includes("://")) {
    const url = new URL(host);
    const params = new URLSearchParams(window.location.search);
    const token = params.get("osc_token") || window.localStorage.getItem("oscBridgeToken");
    if (token) {
      url.searchParams.set("token", token);
    }
    return url.toString();
  }

  const protocol = window.location.protocol === "https:" ? "wss" : "ws";
  const hostname = host || window.location.hostname || "localhost";
  const url = new URL(`${protocol}://${hostname}`);
  if (!url.port) {
    url.port = "9001";
  }
  const params = new URLSearchParams(window.location.search);
  const token = params.get("osc_token") || window.localStorage.getItem("oscBridgeToken");
  if (token) {
    url.searchParams.set("token", token);
  }
  return url.toString();
}

function ensureMidiPlaceholder(message) {
  if (midiSelect.options.length > 0) return;
  const option = document.createElement("option");
  option.value = "";
  option.textContent = message;
  midiSelect.appendChild(option);
}

function connectCurrentOsc() {
  if (oscHostError) {
    renderConnections();
    return;
  }

  try {
    const url = makeOscUrl(oscHost);
    connectOscBridge(url);
  } catch (error) {
    oscStatus = "disconnected";
    oscStatusDetail = error instanceof Error ? error.message : "OSC bridge failed";
    renderStatus();
    renderConnections();
  }
}

async function startQrScanner() {
  qrScanner.classList.remove("hidden");
  qrStatus.textContent = "Starting camera...";

  if (!navigator.mediaDevices?.getUserMedia) {
    qrStatus.textContent = "Camera access is not available in this browser.";
    return;
  }

  if (!("BarcodeDetector" in window)) {
    qrStatus.textContent = "QR scanning is not available in this browser.";
    return;
  }

  try {
    qrDetector = new window.BarcodeDetector({ formats: ["qr_code"] });
    qrStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: { ideal: "environment" } },
      audio: false
    });
    qrVideo.srcObject = qrStream;
    await qrVideo.play();
    qrStatus.textContent = "Point the camera at an OSC host QR code.";
    scanQrFrame();
  } catch (error) {
    const message = error instanceof Error ? error.message : "Camera failed";
    qrStatus.textContent = message;
    addLog(`QR scanner failed: ${message}`);
  }
}

function stopQrScanner() {
  if (qrScanFrame) {
    window.cancelAnimationFrame(qrScanFrame);
    qrScanFrame = null;
  }
  if (qrStream) {
    qrStream.getTracks().forEach((track) => track.stop());
    qrStream = null;
  }
  qrVideo.pause();
  qrVideo.srcObject = null;
  qrDetector = null;
  qrScanner.classList.add("hidden");
}

async function scanQrFrame() {
  if (!qrDetector || qrScanner.classList.contains("hidden")) return;
  try {
    const barcodes = await qrDetector.detect(qrVideo);
    const rawValue = barcodes.find((barcode) => barcode.rawValue)?.rawValue;
    if (rawValue) {
      applyOscHostFromQr(rawValue);
      stopQrScanner();
      return;
    }
  } catch (error) {
    const message = error instanceof Error ? error.message : "QR scan failed";
    qrStatus.textContent = message;
  }
  qrScanFrame = window.requestAnimationFrame(scanQrFrame);
}

function applyOscHostFromQr(payload) {
  const host = extractHostFromQr(payload);
  oscHostInput.value = host;
  handleOscHostCommit();
  addLog("OSC host scanned from QR");
}

function extractHostFromQr(payload) {
  const trimmed = String(payload ?? "").trim();
  try {
    const parsed = new URL(trimmed);
    if (!parsed.hostname) return trimmed;
    const scheme = parsed.protocol.replace(":", "").toLowerCase();
    const port = parsed.port ? `:${parsed.port}` : "";
    return scheme ? `${scheme}://${parsed.hostname}${port}` : parsed.hostname;
  } catch {
    return trimmed;
  }
}

function addLog(message) {
  const timestamp = new Date().toLocaleTimeString("en-US", { hour12: false });
  logs.push({ timestamp, message });
  if (logs.length > MAX_LOG_ENTRIES) {
    logs.splice(0, logs.length - MAX_LOG_ENTRIES);
  }
  renderLogs();
}

function isTogglePad(pad) {
  if (pad.ui?.type === "slider") return false;
  if (pad.ui?.role === "patternBank") return true;
  if (typeof pad.toggle === "boolean") return pad.toggle;
  return pad.mode === "toggle";
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

function setPadState(id, nextState) {
  padState.set(id, nextState);
}

function setPadUi(id, on) {
  const element = padElements.get(id);
  if (!element) return;
  if (!element.classList.contains("button-pad")) return;
  element.classList.toggle("on", on);
  element.classList.toggle("off", !on);
}

function recordSent(id, payload) {
  const previous = getPadState(id);
  setPadState(id, {
    on: previous.on,
    lastSent: { ...(previous.lastSent ?? {}), ...payload },
    updatedAt: new Date().toISOString()
  });
}

function handleTogglePad(pad) {
  const current = getPadState(pad.id).on;
  const nextOn = !current;
  if (nextOn) {
    const profile = currentProfile();
    if (profile) {
      enforceExclusiveGroup(pad, profile);
    }
  }

  setPadState(pad.id, {
    on: nextOn,
    lastSent: getPadState(pad.id).lastSent,
    updatedAt: new Date().toISOString()
  });
  setPadUi(pad.id, nextOn);
  addLog(`Pad ${pad.id} ${nextOn ? "on" : "off"}`);
  sendOutputs(pad, nextOn ? "on" : "off");
}

function handleMomentaryPadPress(pad) {
  if (getPadState(pad.id).on) return;
  setPadState(pad.id, {
    on: true,
    lastSent: getPadState(pad.id).lastSent,
    updatedAt: new Date().toISOString()
  });
  setPadUi(pad.id, true);
  addLog(`Pad ${pad.id} on`);
  sendOutputs(pad, "on");
}

function handleMomentaryPadRelease(pad) {
  if (!getPadState(pad.id).on) return;
  setPadState(pad.id, {
    on: false,
    lastSent: getPadState(pad.id).lastSent,
    updatedAt: new Date().toISOString()
  });
  setPadUi(pad.id, false);
  addLog(`Pad ${pad.id} off`);
  sendOutputs(pad, "off");
}

function handlePatternBankClick(pad) {
  const ui = getUiConfig(pad);
  if (ui.role !== "patternBank") return;
  const bank = Number.isFinite(ui.bank) ? ui.bank : 0;
  setProfilePatternBank(currentProfileId, bank);
  syncPatternBankState();
  renderSurface(currentProfile());
}

function enforceExclusiveGroup(pad, profile) {
  const group = getGroupInfo(pad);
  if (!group?.exclusive) return;

  profile.pads.forEach((other) => {
    if (other.id === pad.id) return;
    const otherGroup = getGroupInfo(other);
    if (!otherGroup || otherGroup.id !== group.id) return;
    if (!isTogglePad(other)) return;

    setPadState(other.id, {
      on: false,
      lastSent: getPadState(other.id).lastSent,
      updatedAt: new Date().toISOString()
    });
    setPadUi(other.id, false);
    sendOutputs(other, "off");
  });
}

function getUiConfig(pad) {
  const ui = pad.ui ?? {};
  const min = Number.isFinite(ui.min) ? ui.min : 0;
  const max = Number.isFinite(ui.max) ? ui.max : 127;
  const step = Number.isFinite(ui.step) ? ui.step : 1;
  const fallbackInitial = Number.isFinite(pad.midi?.offValue) ? pad.midi.offValue : min;
  const initial = Number.isFinite(ui.initial) ? ui.initial : fallbackInitial;
  return {
    type: ui.type ?? "button",
    role: ui.role ?? null,
    target: typeof ui.target === "string" ? ui.target : null,
    bank: Number.isFinite(ui.bank) ? ui.bank : null,
    min,
    max,
    step,
    initial: Math.min(Math.max(initial, min), max),
    showValue: ui.showValue !== false
  };
}

function getProfileControls(profileId) {
  const key = profileId ?? "_";
  if (!profileControls.has(key)) {
    profileControls.set(key, {
      velocity: 100,
      patternBank: 0,
      velocityOverrides: new Map()
    });
  }
  return profileControls.get(key);
}

function getProfileVelocity(profileId) {
  return getProfileControls(profileId).velocity;
}

function setProfileVelocity(profileId, value) {
  getProfileControls(profileId).velocity = value;
}

function getProfilePatternBank(profileId) {
  return getProfileControls(profileId).patternBank;
}

function setProfilePatternBank(profileId, value) {
  getProfileControls(profileId).patternBank = value;
}

function getProfileVelocityOverride(profileId, padId) {
  if (!padId) return null;
  return getProfileControls(profileId).velocityOverrides.get(padId) ?? null;
}

function setProfileVelocityOverride(profileId, padId, value) {
  if (!padId) return;
  getProfileControls(profileId).velocityOverrides.set(padId, value);
}

function syncPatternBankState() {
  const profile = currentProfile();
  if (!profile) return;
  const bank = getProfilePatternBank(currentProfileId);
  profile.pads.forEach((pad) => {
    if (pad.ui?.role !== "patternBank") return;
    const isOn = pad.ui?.bank === bank;
    setPadState(pad.id, {
      on: isOn,
      lastSent: getPadState(pad.id).lastSent,
      updatedAt: new Date().toISOString()
    });
  });
}

function sliderValueForPad(pad) {
  if (pad.ui?.role === "velocity") {
    return getProfileVelocity(currentProfileId);
  }
  if (pad.ui?.role === "velocityOverride") {
    const target = pad.ui?.target;
    const override = target ? getProfileVelocityOverride(currentProfileId, target) : null;
    if (Number.isFinite(override)) return override;
    return getProfileVelocity(currentProfileId);
  }
  if (sliderValues.has(pad.id)) {
    return sliderValues.get(pad.id);
  }
  return getUiConfig(pad).initial;
}

function handleSliderChange(pad, value) {
  const ui = getUiConfig(pad);
  let clamped = Math.min(Math.max(value, ui.min), ui.max);

  if (ui.role === "velocity") {
    setProfileVelocity(currentProfileId, clamped);
    sliderValues.set(pad.id, clamped);
    recordSent(pad.id, { ui: { role: "velocity", value: clamped } });
    return;
  }

  if (ui.role === "velocityOverride") {
    if (ui.target) {
      setProfileVelocityOverride(currentProfileId, ui.target, clamped);
    }
    sliderValues.set(pad.id, clamped);
    recordSent(pad.id, { ui: { role: "velocityOverride", value: clamped, target: ui.target } });
    return;
  }

  if (ui.role === "pattern") {
    if (getProfilePatternBank(currentProfileId) === 1) {
      clamped = Math.min(clamped, 121);
    }
    sliderValues.set(pad.id, clamped);
    sendProgramValue(pad, clamped);
    recordSent(pad.id, { ui: { role: "pattern", value: clamped } });
    return;
  }

  sliderValues.set(pad.id, clamped);
  if (oscEnabled && pad.osc) {
    sendOscValue(pad, clamped);
    addLog(`OSC ${pad.osc.address} = ${clamped}`);
    recordSent(pad.id, { osc: { address: pad.osc.address, value: clamped } });
  }
  if (pad.midi) {
    sendSliderValue(pad, clamped);
  }
}

function sendSliderValue(pad, value) {
  const now = performance.now();
  const last = lastSliderSend.get(pad.id) ?? 0;
  const elapsed = now - last;
  if (elapsed >= SLIDER_SEND_INTERVAL_MS) {
    lastSliderSend.set(pad.id, now);
    sendMidiForSlider(pad, value);
    return;
  }

  pendingSliderValues.set(pad.id, value);
  if (pendingSliderTimers.has(pad.id)) return;
  const delay = Math.max(SLIDER_SEND_INTERVAL_MS - elapsed, 0);
  const timer = window.setTimeout(() => {
    pendingSliderTimers.delete(pad.id);
    const pendingValue = pendingSliderValues.get(pad.id);
    if (!Number.isFinite(pendingValue)) return;
    pendingSliderValues.delete(pad.id);
    lastSliderSend.set(pad.id, performance.now());
    sendMidiForSlider(pad, pendingValue);
  }, delay);
  pendingSliderTimers.set(pad.id, timer);
}

function sendMidiForSlider(pad, value) {
  if (!pad.midi) return;
  if (pad.midi.type === "cc") {
    sendCC(midiOutput, pad.midi.channel, pad.midi.cc, value);
    addLog(`MIDI CC ${pad.midi.cc} ch ${pad.midi.channel} = ${value}`);
    recordSent(pad.id, { midi: { type: "cc", value } });
    return;
  }
  if (pad.midi.type === "program") {
    sendProgramValue(pad, value);
  }
}

function sendProgramValue(pad, value) {
  if (!pad.midi || pad.midi.type !== "program") return;
  const ui = getUiConfig(pad);
  const clamped = Math.min(Math.max(value, ui.min), ui.max);

  let program = clamped;
  let bankMsb = pad.midi.bankMsb;
  let bankLsb = pad.midi.bankLsb;

  if (pad.midi.programBankMode === "electribePattern") {
    const patternBank = getProfilePatternBank(currentProfileId);
    bankMsb = 0;
    bankLsb = patternBank;
    if (patternBank === 1) {
      program = Math.min(clamped, 121);
    }
  }

  sendProgramChange(midiOutput, pad.midi.channel, program, bankMsb, bankLsb);
  addLog(`MIDI Program ch ${pad.midi.channel} = ${program}`);
  recordSent(pad.id, { midi: { type: "program", value: clamped } });
}

function sendOutputs(pad, state, { suppressOsc = false, oscQueuePolicy = null } = {}) {
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
      addLog(`MIDI note ${pad.midi.note} ch ${pad.midi.channel} ${state}`);
      recordSent(pad.id, { midi: { type: "note", state } });
    } else if (pad.midi.type === "cc") {
      const value = state === "on" ? (pad.midi.onValue ?? 127) : (pad.midi.offValue ?? 0);
      sendCC(midiOutput, pad.midi.channel, pad.midi.cc, value);
      addLog(`MIDI CC ${pad.midi.cc} ch ${pad.midi.channel} = ${value}`);
      recordSent(pad.id, { midi: { type: "cc", state } });
    } else if (pad.midi.type === "program" && state === "on") {
      sendProgramValue(pad, pad.midi.program ?? 1);
    } else if (pad.midi.type === "realtime" && state === "on") {
      sendRealtime(midiOutput, pad.midi.realtime);
      addLog(`MIDI realtime ${pad.midi.realtime}`);
      recordSent(pad.id, { midi: { type: "realtime", state } });
    }
  }

  if (!suppressOsc && oscEnabled && pad.osc) {
    sendOscMessage(oscQueuePolicy ? { ...pad, queuePolicy: oscQueuePolicy } : pad, state);
    addLog(`OSC ${pad.osc.address} ${state}`);
    recordSent(pad.id, { osc: { address: pad.osc.address, state } });
  }
}

function dumpState() {
  const snapshot = {};
  padState.forEach((value, key) => {
    snapshot[key] = value;
  });
  console.log("Pad state snapshot:", snapshot);
  return snapshot;
}

function safeBlackout() {
  const allPads = profiles.flatMap((profile) => profile.pads ?? []);
  const blackoutPads = allPads.filter((pad) =>
    pad.osc?.address === "/rig/state/blackout" ||
    pad.id === "vid_state_blackout" ||
    pad.osc?.address === "/nw_wrld/feed/blackout" ||
    pad.id === "nw_feed_blackout"
  );
  const overlayPads = allPads.filter((pad) =>
    pad.id?.startsWith("nw_overlay_") ||
    pad.id?.startsWith("nw_fx_") ||
    pad.osc?.address?.includes("/overlay/") ||
    pad.osc?.address?.includes("/fx/")
  );
  const canSendOsc = oscEnabled && oscStatus === "connected";

  if (!canSendOsc && [...overlayPads, ...blackoutPads].some((pad) => pad.osc)) {
    addLog("Safe blackout OSC dropped: OSC is disabled or disconnected");
  }

  overlayPads.forEach((pad) => {
    setPadState(pad.id, {
      on: false,
      lastSent: getPadState(pad.id).lastSent,
      updatedAt: new Date().toISOString()
    });
    setPadUi(pad.id, false);
    sendOutputs(pad, "off", { suppressOsc: !canSendOsc, oscQueuePolicy: "never" });
  });

  blackoutPads.forEach((pad) => {
    setPadState(pad.id, {
      on: true,
      lastSent: getPadState(pad.id).lastSent,
      updatedAt: new Date().toISOString()
    });
    setPadUi(pad.id, true);
    sendOutputs(pad, "on", { suppressOsc: !canSendOsc, oscQueuePolicy: "never" });
  });
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function buildPadMatrix(pads, rows, cols) {
  const matrix = Array.from({ length: rows }, () => Array.from({ length: cols }, () => null));
  pads.forEach((pad, index) => {
    const defaultRow = Math.floor(index / cols);
    const defaultCol = index % cols;
    const row = Number.isFinite(pad.row) ? pad.row : defaultRow;
    const col = Number.isFinite(pad.col) ? pad.col : defaultCol;
    if (row < 0 || row >= rows || col < 0 || col >= cols) return;
    if (!matrix[row][col]) {
      matrix[row][col] = pad;
    }
  });
  return matrix;
}

async function main() {
  try {
    await loadMappings();
    initPadState();
    bindUi();

    oscHostInput.value = oscHost;
    logEnabledToggle.checked = logsEnabled;

    subscribeOscStatus(({ status, detail = "", queuedCount = 0 }) => {
      oscStatus = status;
      oscStatusDetail = detail;
      oscQueuedCount = queuedCount;
      renderStatus();
      renderConnections();
    });

    try {
      midiAccess = await initMIDI(populateMidiOutputs);
      if (!midiAccess) {
        addLog("WebMIDI unavailable; OSC controls remain available");
      }
    } catch (error) {
      midiAccess = null;
      const message = error instanceof Error ? error.message : "permission rejected";
      addLog(`WebMIDI unavailable: ${message}; OSC controls remain available`);
    }

    chooseInitialProfile();
    renderAll();
    addLog("Loaded mappings.json");

    if (oscEnabled) {
      oscHostError = validateOscHost(oscHost);
      connectCurrentOsc();
    }
  } catch (error) {
    console.error(error);
    surfaceTitle.textContent = "Failed to load mappings";
    surfaceMeta.textContent = error instanceof Error ? error.message : "Unknown error";
    emptyState.classList.remove("hidden");
  }
}

window.dumpState = dumpState;
window.safeBlackout = safeBlackout;

main();
