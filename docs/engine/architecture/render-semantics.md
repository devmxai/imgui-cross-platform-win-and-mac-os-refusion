# Render Semantics

This is the canonical rendering flow for preview and export.

```text
Open Folder project files
  -> UnitedGate
  -> HyperFrame Core
  -> FrameDescriptor
  -> RenderGraph
  -> FXPassGraph
  -> platform adapter
  -> FinalFrameSurface
  -> FinalFrameStream
  -> encoder
```

## Source Of Truth

```text
composition.json
timeline.json
assets/assets.json
```

No renderer may interpret hidden state that is not represented through the project contract or a Core-generated render contract.

## Preview

Preview adapters may trade quality for interactivity only when Core/platform diagnostics clearly report the fallback.

Preview must not advertise support for an effect when required Core or adapter gates are missing.

## Timeline Clock / Accepted Frame Rule

Platform adapters own project time through one timeline clock authority. UI state, DOM events, requestAnimationFrame, HTML media playback state, and CSS animation time must not become independent timeline clocks.

```text
UI command
-> platform adapter timeline clock
-> Core-generated frame request
-> platform source provider decoded-frame readiness
-> renderer transaction
-> accepted/preserved/rejected frame state
-> UI playhead/state display
```

The visible playhead follows accepted render transactions. It must not advance ahead of rendered truth because wall-clock time, HTMLVideoElement.currentTime, or UI state changed.

When media for a requested time is not decoded/drawable yet, the adapter may preserve the previous complete frame with diagnostics. It must not present partial, guessed, blank, stale, or degraded frames as successful project pixels.

## Export

Export must use the same Core render semantics as preview, with stricter quality gates and deterministic frame production.

Encoders receive final frames. They do not parse layers, effects, animations, or timeline meaning.
