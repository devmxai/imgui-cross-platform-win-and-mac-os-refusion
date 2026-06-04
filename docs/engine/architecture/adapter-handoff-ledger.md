# Browser And Windows Adapter Handoff Ledger

This ledger records implementation handoffs for the Browser and Windows adapter workstream.

## Handoff 2026-05-31-G0-B0-B1-start

```text
date: 2026-05-31
classification: docs/test work + Browser UI shell work
milestones: G0, B0, B1
activePixelAuthority: transitional Web V2 WebGL2 path
backendState: webgl2-degraded; WebGPU professional backend pending
protectedPaths: src/core/**, src/engine/**, macos-native/**, scenes, user workspaces
filesTouched: docs, verifier scripts, package scripts, apps/web/ui-v2, apps/web/App.tsx shell composition only
commandsRun: npm run architecture:verify; npm run web:v2:verify; npm run web:professional:audit; npm run windows:structure:verify; npm run build; git diff --check
results: passed; build completed with existing Vite chunk-size warning
knownGaps: Browser command-handler orchestration still needs extraction behind the adapter session boundary; WebRenderGraph adapter, WebGPU backend, WebCodecs deterministic provider, visual parity, performance gates remain pending
nextAllowedAction: continue B1 adapter-session command boundary extraction, then run B2 contract sufficiency review
```

## Handoff 2026-05-31-B1-ui-command-gate

```text
date: 2026-05-31
classification: Browser UI shell work only
milestone: B1 in-progress at 60%
activePixelAuthority: transitional Web V2 WebGL2 path unchanged
protectedPaths: src/core/**, src/engine/**, macos-native/**, scenes, user workspaces
filesTouched: apps/web/App.tsx; apps/web/ui-v2/**
commandsRun: npm run lint; npm run build; npm run golden:verify; git diff --check; Browser local smoke verification
results: passed; Browser editor shell opened without console warnings or errors
passedGate: toolbar, library rail, selection, playback, seek, and scrub UI interactions cross one compact Browser UI command gate
knownGaps: App.tsx still owns adapter orchestration; Browser professional WebGPU and WebCodecs packages remain pending
nextAllowedAction: add a thin Browser UI command router and an automated UI-only boundary verifier without changing renderer, FX, media decode, Core, Engine, or macOS behavior
```

## Handoff 2026-05-31-B1-ui-router-boundary

```text
date: 2026-05-31
classification: Browser UI shell work only
milestone: B1 in-progress at 80%
activePixelAuthority: transitional Web V2 WebGL2 path unchanged
protectedPaths: src/core/**, src/engine/**, macos-native/**, scenes, user workspaces
filesTouched: apps/web/App.tsx; apps/web/services/browserUiCommandRouter.ts; apps/web/ui-v2/**; scripts/platform/verify-browser-ui-shell.mjs; package.json
passedGate: Browser UI router is thin and renderer-agnostic; automated verifier rejects Core, Engine, platform renderer, canvas, frame-loop, media-decode, GPU-execution, and FX interpretation tokens inside apps/web/ui-v2 code
knownGaps: remaining App.tsx orchestration cleanup; Browser RenderGraph adapter, WebGPU backend, WebCodecs deterministic provider, parity, and performance gates remain pending
nextAllowedAction: finish B1 orchestration cleanup, then perform B2 contract sufficiency review before writing WebRenderGraph code
```

## Handoff 2026-05-31-B2-web-render-graph-foundation

```text
date: 2026-05-31
classification: Browser adapter implementation only
milestone: B2 in-progress at 60%
activePixelAuthority: transitional Web V2 WebGL2 path unchanged
protectedPaths: src/core/**, src/engine/**, macos-native/**, scenes, user workspaces
contractReview: accepted; existing CanonicalFrameRequest already carries FrameDescriptor, FXPassGraph, quality policy, source provider boundary, and diagnostics
filesTouched: src/platforms/web/v2/renderer/graph/**; src/platforms/web/v2/renderer/WebRenderEngineV2.ts; src/platforms/web/v2/index.ts; scripts/platform/verify-web-v2-adapter.mjs; scripts/platform/audit-web-professional-readiness.mjs; docs/platforms/web-rendergraph-sufficiency-review.md
passedGate: transitional renderer creates and validates ordered WebRenderGraph nodes from CanonicalFrameRequest before presentation; WebGL2 and Canvas fallback consume validated graph-node layer order
knownGaps: per-node FX pass resolution still reads the canonical request FXPassGraph; WebGPU backend, WebCodecs deterministic provider, parity, and performance gates remain pending
nextAllowedAction: route per-node pass execution through validated WebRenderGraph nodes while preserving canonical FXPassGraph meaning, then add WebGPU capability-registry scaffolding
```
