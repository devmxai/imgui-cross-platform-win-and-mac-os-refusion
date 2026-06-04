# ADR-008: Native Hardware-Required Export

Status: accepted.

Date: 2026-06-01.

## Decision

Professional Native export is fail-closed:

```text
UnitedGate project snapshot
-> canonical HyperFrame IR
-> integer frame-index export loop
-> selected physical Metal GPU
-> Metal RenderGraph renderer
-> VideoToolbox hardware encoder required
-> MP4
-> export report
```

Required:

```text
enumerate Metal devices
choose the strongest compatible device
enumerate hardware video encoders
create a VideoToolbox proof session
require kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder
verify kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder
pass the required hardware encoder specification to AVAssetWriter
record GPU and encoder evidence in the export report
```

Forbidden:

```text
Quartz compatibility renderer fallback
software video encoder fallback
silent unsupported FX export
frame dropping
preview clock as export authority
```

The Browser UI remains a command shell. A separate local Native Bridge work
package will transfer an export job and original assets to this executor.
