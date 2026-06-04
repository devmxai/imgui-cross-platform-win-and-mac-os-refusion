import Foundation

enum NativeFrameRendererFactory {
    static func makeRenderer(
        workspaceURL: URL,
        target: NativeFrameRenderTarget,
        requestedBackend: NativeExportBackend,
        hardware: NativeHardwareExportCapability
    ) throws -> NativeFrameRendererSelection {
        guard let metal = MetalRenderGraphFrameRenderer(
            workspaceURL: workspaceURL,
            target: target,
            device: hardware.metalDevice
        ) else {
            throw NativeExportError.hardwareMetalRendererInitializationFailed(hardware.metalDeviceName)
        }
        return NativeFrameRendererSelection(
            renderer: metal,
            requestedBackend: requestedBackend,
            actualBackend: metal.backendName,
            fallbackReason: nil
        )
    }
}
