# MIGRATION

## OSC toggles with implicit args

Older mappings often used a single `args: [1]` value for toggle pads. The
interop contract now expects explicit on/off semantics for toggles.

Before:

```json
{
  "toggle": true,
  "osc": {
    "address": "/nw_wrld/feed/enable",
    "args": [1]
  }
}
```

After (required for toggle pads):

```json
{
  "toggle": true,
  "osc": {
    "address": "/nw_wrld/feed/enable",
    "args": [1],
    "onArgs": [1],
    "offArgs": [0]
  }
}
```

Notes:
- Keep `args` only as the generic/on value alongside explicit `onArgs` and
  `offArgs`; runtime mappings reject implicit toggle release semantics.
- For momentary pads, `args` alone is still valid.
- If your off state uses a different value, set `offArgs` accordingly.
