# Current macOS Native Adapter Map

Status: transitional.

The current macOS adapter implementation still lives under:

```text
macos-native/Sources/MakelabMac
```

The future platform adapter home is:

```text
src/platforms/macos
```

Do not move Swift files into `src/platforms/macos` until the Swift package split is planned and verified.

## Current Core Contract Bridge

```text
CanonicalHyperFrameBridge.swift
UnitedGate.swift
WorkspaceModels.swift
RenderGraph.swift
FXPassGraph.swift
FXRegistry.swift
MotionBlurQualityPlanner.swift
```

## Current Native Execution Adapter

```text
NativeFrameRenderer.swift
NativeFrameRendererFactory.swift
NativeRenderEngine.swift
MetalFXRuntime.swift
MetalRenderGraphFrameRenderer.swift
NativeTimelineExporter.swift
```

## App Shell Files That Must Stay Out Of Adapter Semantics

```text
MakelabMacApp.swift
ContentView.swift
EditorState.swift
ExportSettings.swift
```

## Adapter Rule

macOS adapter code may execute Core contracts with Metal, AVFoundation, CVPixelBuffer, and native export surfaces. It must not define independent FX names, timeline meaning, animation behavior, sample-planner semantics, or export semantics.

## FX Semantics Parity

`FXRegistry.swift` is a native mirror. It is not the source of truth.

Source of truth:

```text
src/core/hyperframe/fx/fxRegistry.manifest.json
```

Guard:

```text
npm run architecture:verify
```

The guard fails if macOS declares an FX canonical name, alias, schema parameter, or capability support entry that does not exist in the Core manifest.
