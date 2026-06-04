# macOS Platform Adapter

This folder executes HyperFrame Core contracts on macOS technologies.

## Allowed

```text
Metal execution
AVFoundation decode/encode integration
CVPixelBuffer and texture handoff
native preview adapter
native export adapter
macOS capability diagnostics
```

## Forbidden

```text
canonical FX names
FX schemas or defaults
animation semantics
timeline semantics
sample planner semantics not generated from or checked against Core
export meaning
```

Current native source remains in:

```text
macos-native/Sources/MakelabMac
```

Do not move it blindly. Split app shell and adapter code only after boundary checks and parity tests exist.

## Current Transitional Map

Read:

```text
src/platforms/macos/current-native-adapter-map.md
apps/macos/current-app-shell.md
```

Run:

```text
npm run macos:structure:verify
```
