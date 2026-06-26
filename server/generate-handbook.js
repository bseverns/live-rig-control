import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const mappingsPath = path.resolve(__dirname, "../src/mappings.json");
const outputPath = path.resolve(__dirname, "../docs/operator-handbook.md");

const mappings = JSON.parse(fs.readFileSync(mappingsPath, "utf8"));
const profiles = Object.entries(mappings.profiles ?? {})
  .map(([id, profile]) => ({ id, ...profile }))
  .sort((left, right) => {
    const sectionRank = { show: 0, sound: 1, video: 2, setup: 3 };
    const leftSection = sectionRank[left.section] ?? 99;
    const rightSection = sectionRank[right.section] ?? 99;
    if (leftSection !== rightSection) return leftSection - rightSection;
    const leftOrder = Number.isFinite(left.order) ? left.order : 999;
    const rightOrder = Number.isFinite(right.order) ? right.order : 999;
    if (leftOrder !== rightOrder) return leftOrder - rightOrder;
    return (left.label || left.id).localeCompare(right.label || right.id);
  });

function transportFor(pad) {
  const parts = [];
  if (pad.midi) {
    if (pad.midi.type === "note") parts.push(`MIDI note ${pad.midi.note} ch ${pad.midi.channel}`);
    else if (pad.midi.type === "cc") parts.push(`MIDI CC ${pad.midi.cc} ch ${pad.midi.channel}`);
    else if (pad.midi.type === "program") parts.push(`MIDI program ch ${pad.midi.channel}`);
    else if (pad.midi.type === "realtime") parts.push(`MIDI realtime ${pad.midi.realtime}`);
  }
  if (pad.osc) parts.push(`OSC ${pad.osc.address}`);
  if (parts.length === 0 && pad.ui) parts.push(`UI ${pad.ui.role || pad.ui.type || "control"}`);
  return parts.join("<br>");
}

function layoutLabel(profile) {
  const layout = profile.layout?.kind ?? "mappedGrid";
  return profile.layout?.minCardWidth
    ? `${layout}, min card ${profile.layout.minCardWidth}px`
    : layout;
}

const lines = [
  "# Live Rig Control Operator Handbook",
  "",
  "Generated from `src/mappings.json`. Edit the mapping, then run `npm --prefix server run generate-handbook`.",
  "",
  "| Profile | Section | Layout | Controls |",
  "| --- | --- | --- | --- |"
];

for (const profile of profiles) {
  lines.push(`| ${profile.label || profile.id} | ${profile.section || "show"} | ${layoutLabel(profile)} | ${(profile.pads ?? []).length} |`);
}

for (const profile of profiles) {
  lines.push("", `## ${profile.label || profile.id}`, "");
  lines.push(`- ID: \`${profile.id}\``);
  lines.push(`- Section: \`${profile.section || "show"}\``);
  lines.push(`- Layout: \`${layoutLabel(profile)}\``);
  lines.push("");
  lines.push("| Pad | Label | Risk | Queue | Transport | Notes |");
  lines.push("| --- | --- | --- | --- | --- | --- |");
  for (const pad of profile.pads ?? []) {
    const notes = String(pad.notes || "").replaceAll("|", "\\|");
    lines.push(`| ${[
      `\`${pad.id}\``,
      pad.label || pad.id,
      pad.risk || "medium",
      pad.queuePolicy || "ttl",
      transportFor(pad),
      notes
    ].join(" | ")} |`);
  }
}

fs.writeFileSync(outputPath, `${lines.join("\n")}\n`);
console.log(`Wrote ${path.relative(path.resolve(__dirname, ".."), outputPath)}`);
