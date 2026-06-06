# Shared UI Boundary

This folder owns the shared Dear ImGui editor shell.

Allowed:

```text
draw toolbar, asset panel, stage, transport, timeline, inspectors, diagnostics
display accepted workspace state
display accepted FinalFrameSurface texture
emit command names and payloads
```

Forbidden:

```text
decode media
compose preview pixels
interpret FX
own playback time
own export frames
write project files directly
fork behavior per platform
```

If a UI gesture changes project state, emit a command and let shared authoring
and Gates decide whether the change is accepted.
