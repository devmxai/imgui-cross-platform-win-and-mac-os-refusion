# Authoring Boundary

This folder owns shared editor authoring services.

Allowed:

```text
validate project edits
apply accepted commands
write canonical project files atomically
protect accepted project state
return diagnostics
```

Forbidden:

```text
native file picker ownership
platform render ownership
FX execution
preview generation
export encoding
```

Typical flow:

```text
UI command
-> ProjectAuthoringService
-> Gate validation
-> accepted project state
-> platform render request
```
