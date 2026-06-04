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
