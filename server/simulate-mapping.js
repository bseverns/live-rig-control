import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function parseArgs(argv) {
  const opts = {};
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === "--mappings" || arg === "-m") {
      opts.mappings = argv[i + 1];
      i += 1;
    } else if (arg === "--id") {
      opts.id = argv[i + 1];
      i += 1;
    } else if (arg === "--state" || arg === "-s") {
      opts.state = argv[i + 1];
      i += 1;
    } else if (arg === "--value" || arg === "-v") {
      opts.value = argv[i + 1];
      i += 1;
    } else if (arg === "--help" || arg === "-h") {
      opts.help = true;
    }
  }
  return opts;
}

function usage() {
  console.log("Usage: node simulate-mapping.js --id <padId> [--state on|off] [--value 0..127] [--mappings <path>]");
  console.log("Button default: --state on. Sliders require --value. Mappings default: ../src/mappings.json");
}

function normalizeState(state) {
  const next = (state || "on").toLowerCase();
  if (next !== "on" && next !== "off") {
    throw new Error(`Invalid state "${state}". Use "on" or "off".`);
  }
  return next;
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

function isTogglePad(pad) {
  if (typeof pad.toggle === "boolean") return pad.toggle;
  if (pad.mode) return pad.mode === "toggle";
  return false;
}

function resolveOscArg(arg, { state, value }) {
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

function resolveOscArgs(osc, { state, value }) {
  let args;
  if (Number.isFinite(value)) {
    args = osc.args ?? [];
  } else if (state === "on") {
    args = osc.onArgs ?? osc.args ?? [];
  } else {
    args = osc.offArgs ?? [0];
  }
  return args.map((arg) => resolveOscArg(arg, { state, value }));
}

function normalizeValue(rawValue, pad) {
  if (rawValue === undefined) return null;
  const value = Number(rawValue);
  const min = pad.ui?.min ?? 0;
  const max = pad.ui?.max ?? 127;
  if (!Number.isFinite(value) || !Number.isInteger(value) || value < min || value > max) {
    throw new Error(`Invalid value "${rawValue}". Use an integer from ${min} to ${max}.`);
  }
  return value;
}

function isSlider(pad) {
  return pad.ui?.type === "slider";
}

function buildOutputs(pad, state, value = null) {
  const outputs = [];
  if (pad.osc) {
    const args = resolveOscArgs(pad.osc, { state, value });
    outputs.push(`OSC -> ${pad.osc.address} ${JSON.stringify(args)}`);
  }
  if (pad.midi) {
    if (pad.midi.type === "note") {
      const velocity = state === "on"
        ? pad.midi.onVelocity ?? 100
        : pad.midi.offVelocity ?? 0;
      outputs.push(
        `MIDI -> note ch${pad.midi.channel} note ${pad.midi.note} vel ${velocity}`
      );
    } else if (pad.midi.type === "cc") {
      const outputValue = Number.isFinite(value) ? value : state === "on"
        ? pad.midi.onValue ?? 127
        : pad.midi.offValue ?? 0;
      outputs.push(
        `MIDI -> cc ch${pad.midi.channel} cc ${pad.midi.cc} val ${outputValue}`
      );
    } else if (pad.midi.type === "program") {
      if (state === "on" || Number.isFinite(value)) {
        const bankMsb = Number.isFinite(pad.midi.bankMsb) ? pad.midi.bankMsb : null;
        const bankLsb = Number.isFinite(pad.midi.bankLsb) ? pad.midi.bankLsb : null;
        const bankInfo = bankMsb !== null || bankLsb !== null
          ? ` bank ${bankMsb ?? "-"},${bankLsb ?? "-"}`
          : "";
        outputs.push(
          `MIDI -> program ch${pad.midi.channel} program ${value ?? pad.midi.program}${bankInfo}`
        );
      }
    } else if (pad.midi.type === "realtime") {
      if (state === "on") {
        outputs.push(`MIDI -> realtime ${pad.midi.realtime}`);
      }
    }
  }
  return outputs;
}

const opts = parseArgs(process.argv.slice(2));
if (opts.help || !opts.id) {
  usage();
  process.exit(opts.help ? 0 : 1);
}

const mappingsPath = path.resolve(__dirname, opts.mappings ?? "../src/mappings.json");
const mappings = JSON.parse(fs.readFileSync(mappingsPath, "utf8"));

let found = null;
let foundProfileId = null;

for (const [profileId, profile] of Object.entries(mappings.profiles ?? {})) {
  for (const pad of profile.pads ?? []) {
    if (pad.id === opts.id) {
      found = pad;
      foundProfileId = profileId;
      break;
    }
  }
  if (found) break;
}

if (!found) {
  console.error(`Pad id "${opts.id}" not found.`);
  process.exit(1);
}

let state = "on";
let value = null;
try {
  state = normalizeState(opts.state);
  value = normalizeValue(opts.value, found);
  if (isSlider(found) && value === null) {
    throw new Error(`Slider "${found.id}" requires --value.`);
  }
} catch (err) {
  console.error(err.message);
  process.exit(1);
}

console.log(`Pad: ${found.id} (profile ${foundProfileId})`);
console.log(value === null ? `State: ${state}` : `Value: ${value}`);
for (const line of buildOutputs(found, value === null ? state : "value", value)) {
  console.log(line);
}

const groupInfo = getGroupInfo(found);
if (state === "on" && groupInfo?.exclusive) {
  const others = [];
  for (const profile of Object.values(mappings.profiles ?? {})) {
    for (const pad of profile.pads ?? []) {
      if (pad.id === found.id) continue;
      const otherGroup = getGroupInfo(pad);
      if (!otherGroup || otherGroup.id !== groupInfo.id) continue;
      if (!isTogglePad(pad)) continue;
      others.push(pad);
    }
  }

  if (others.length > 0) {
    console.log(`Exclusive group "${groupInfo.id}" -> turning off ${others.length} pad(s):`);
    for (const pad of others) {
      for (const line of buildOutputs(pad, "off")) {
        console.log(line);
      }
    }
  }
}
