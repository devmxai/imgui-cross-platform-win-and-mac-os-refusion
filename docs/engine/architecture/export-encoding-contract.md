# Export Encoding Contract

Encoders are not render engines.

## Encoder Input

Encoders may receive:

```text
FinalFrameStream
AudioPCM
metadata needed for muxing
codec settings
container settings
```

Audio is provided by the accepted AudioGraph/audio mixer layer. The encoder may mux
that accepted audio stream with the already-rendered FinalFrameStream, but it must
not become a timeline, visual render, FX, or layer authority.

## Encoder Must Not Parse

```text
timeline layers
FX lists
animation/keyframe definitions
project scene files
RenderGraph meaning
FXPassGraph meaning
```

## BMF Role

BMF is a final-frame encode/mux/output backend. It is not a preview engine, scrub engine, compositor, FX engine, or platform renderer.

## Required Diagnostics

Export paths must report:

```text
selected encoder backend
frame size and frame rate
pixel format
audio format
codec/container settings
fallbacks
unsupported capabilities
```

## Platform Routes

All platform exports share one visual truth:

```text
Gates
-> HyperFrame IR
-> FrameDescriptor
-> RenderGraph
-> FXPassGraph
-> PlatformRenderFrameExecutor
-> FinalFrameSurface
-> platform encoder / mux
```

### macOS Route

Current native route:

```text
FinalFrameSurface (Metal BGRA8)
-> VideoToolbox hardware encoder proof
-> AVAssetWriter H.264 MP4
-> AudioGraph passthrough mux
```

Requirements:

```text
NativeRealtimeResourceScheduler ExportMode is exclusive
VideoToolbox hardware encoder is required
software encoder fallback is rejected
preserved frames are rejected
AudioGraph may mux only after FinalFrameSurface video exists
```

### Windows Route

Future native route:

```text
FinalFrameSurface (D3D texture)
-> Media Foundation hardware encoder proof
-> MP4
-> AudioGraph passthrough mux
```

Requirements:

```text
same ExportMode contract
same frame-index Timeline Truth
same fail-closed frame acceptance
no GDI/CPU renderer fallback
```

### Web Route

Future web route:

```text
FinalFrameSurface stream
-> verified browser/BMF/WebCodecs encoder wrapper
-> MP4/WebM target
```

Requirements:

```text
web encoder is an output backend only
web encoder must not parse timeline, layers, FX, or RenderGraph
no browser canvas preview fallback is allowed to become export truth
```
