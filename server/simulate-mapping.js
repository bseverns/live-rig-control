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
    } else if (arg === "--help" || arg === "-h") {
      opts.help = true;
    }
  }
  return opts;
}

function usage() {
  console.log("Usage: node simulate-mapping.js --id <padId> [--state on|off] [--mappings <path>]");
  console.log("Defaults: --state on --mappings ../src/mappings.json");
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

function resolveOscArgs(osc, state) {
  if (state === "on") {
    return osc.onArgs ?? osc.args ?? [];
  }
  return osc.offArgs ?? [0];
}

function buildOutputs(pad, state) {
  const outputs = [];
  if (pad.osc) {
    const args = resolveOscArgs(pad.osc, state);
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
      const value = state === "on"
        ? pad.midi.onValue ?? 127
        : pad.midi.offValue ?? 0;
      outputs.push(
        `MIDI -> cc ch${pad.midi.channel} cc ${pad.midi.cc} val ${value}`
      );
    } else if (pad.midi.type === "program") {
      if (state === "on") {
        const bankMsb = Number.isFinite(pad.midi.bankMsb) ? pad.midi.bankMsb : null;
        const bankLsb = Number.isFinite(pad.midi.bankLsb) ? pad.midi.bankLsb : null;
        const bankInfo = bankMsb !== null || bankLsb !== null
          ? ` bank ${bankMsb ?? "-"},${bankLsb ?? "-"}`
          : "";
        outputs.push(
          `MIDI -> program ch${pad.midi.channel} program ${pad.midi.program}${bankInfo}`
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
try {
  state = normalizeState(opts.state);
} catch (err) {
  console.error(err.message);
  process.exit(1);
}

console.log(`Pad: ${found.id} (profile ${foundProfileId})`);
console.log(`State: ${state}`);
for (const line of buildOutputs(found, state)) {
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
