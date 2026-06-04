# Platform Adapter Contract

Platform adapters execute Core contracts on real platform technologies.

## Platforms Own

```text
source decode
surface and texture allocation
GPU/CPU execution
shader, compute, and render pass implementation
encoder lifecycle correctness
preview surface handoff
export surface handoff
platform capability diagnostics
```

## Platforms Must Not Own

```text
canonical FX names
FX aliases or schema defaults
timeline field meanings
animation/keyframe semantics
sample planner semantics
export meaning
golden-frame expected behavior
```

## Platform Folders

```text
src/platforms/web
src/platforms/macos
src/platforms/windows
src/platforms/ios
src/platforms/android
```

Current legacy platform code may still exist in old folders until migration phases move it safely.

## FX Semantics Mirror Rule

Platforms may mirror Core FX definitions for native execution only when the mirror is parity-gated.

Current gate:

```text
src/core/hyperframe/fx/fxRegistry.manifest.json
scripts/architecture/verify-fx-semantics-parity.mjs
npm run architecture:verify
```

If a macOS, Web, iOS, or Android adapter needs a new FX name, alias, schema key, or default meaning, the Core manifest and Core normalizer move first. The platform implementation follows after the gate passes.

## Execution Rule

A platform adapter may optimize, cache, tile, batch, or use platform-native GPU passes. It may not change the semantic result unless Core exposes that behavior through a contract or capability gate.
