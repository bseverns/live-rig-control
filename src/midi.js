// WebMIDI helper functions

export async function initMIDI(onChangeOutputs) {
  if (!navigator.requestMIDIAccess) {
    console.warn("WebMIDI not supported in this browser");
    return null;
  }

  const access = await navigator.requestMIDIAccess();
  const outputs = [...access.outputs.values()];

  if (onChangeOutputs) {
    onChangeOutputs(outputs);
  }

  access.onstatechange = () => {
    const newOutputs = [...access.outputs.values()];
    onChangeOutputs && onChangeOutputs(newOutputs);
  };

  return access;
}

export function sendNote(output, channel, note, onVelocity, offVelocity, on) {
  if (!output) return;
  const status = (on ? 0x90 : 0x80) + (channel - 1);
  const velocity = on ? onVelocity ?? 100 : offVelocity ?? 0;
  output.send([status, note, velocity]);
}

export function sendCC(output, channel, cc, value) {
  if (!output) return;
  const status = 0xb0 + (channel - 1);
  output.send([status, cc, value]);
}

export function sendProgramChange(output, channel, program, bankMsb = null, bankLsb = null) {
  if (!output) return;
  const ch = channel - 1;
  if (Number.isFinite(bankMsb)) {
    output.send([0xb0 + ch, 0x00, bankMsb]);
  }
  if (Number.isFinite(bankLsb)) {
    output.send([0xb0 + ch, 0x20, bankLsb]);
  }
  output.send([0xc0 + ch, program]);
}

export function sendRealtime(output, message) {
  if (!output) return;
  const status = {
    start: 0xfa,
    continue: 0xfb,
    stop: 0xfc
  }[message];
  if (!status) return;
  output.send([status]);
}
