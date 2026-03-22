# Contributing

Thanks for contributing to `live-rig-control`.

## Before opening a change

- Open an issue or discussion first for non-trivial changes.
- Keep changes narrowly scoped and explain the operator or developer impact.
- Preserve the mapping-driven behavior across web and iOS clients.

## Development expectations

- Do not commit secrets, signing assets, local `.env` files, or build artifacts.
- Keep `src/mappings.json` and the iOS resource copy aligned when changing mappings.
- Update docs when changing setup, deployment, or control behavior.
- Prefer small pull requests with a clear test or verification note.

## Pull requests

- Describe what changed and why.
- Call out any user-visible behavior changes.
- Include manual verification steps or automated test results.
- Note any follow-up work that is intentionally left out.
