# Timeline Boundary

This folder owns shared timeline helpers used by the ImGui editor.

Allowed:

```text
frame rate helpers
frame/time conversion
time ranges
timeline display math
shared timeline truth utilities
```

Forbidden:

```text
platform clocks
native decoder seeking
preview frame acceptance
platform-specific timeline semantics
```

If a timeline rule changes project meaning, update the Core timeline contract
first, then wire UI and platform display after the contract exists.
