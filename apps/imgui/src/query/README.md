# Query Boundary

This folder owns shared query services for frame and layer truth.

Allowed:

```text
queryFrame
queryLayerAtPixel
frame truth fingerprints
composition-to-viewport transforms
agent-visible diagnostics
```

Forbidden:

```text
platform-only coordinate truth
UI-only pixel truth
rendering shortcuts
timeline reinterpretation
```

Queries must describe the accepted project/frame truth, not an alternate UI
model.
