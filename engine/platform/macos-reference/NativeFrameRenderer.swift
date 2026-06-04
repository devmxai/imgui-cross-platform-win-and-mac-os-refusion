import CoreVideo
import Foundation

struct NativeFrameRenderTarget: Hashable {
    let width: Int
    let height: Int
    let compositionWidth: Int
    let compositionHeight: Int
}

struct NativeFrameRenderSample {
    let graph: RenderGraphSnapshot
    let fxPassGraph: FXPassGraphSnapshot
}

struct NativeFrameRenderContext {
    let frameIndex: Int
    let time: Double
    let fps: Double
    let sample: (Double) -> NativeFrameRenderSample?
}

protocol NativeFrameRenderer: AnyObject {
    var backendName: String { get }
    var target: NativeFrameRenderTarget { get }
    func render(
        graph: RenderGraphSnapshot,
        fxPassGraph: FXPassGraphSnapshot,
        context: NativeFrameRenderContext,
        into pixelBuffer: CVPixelBuffer
    ) throws
}

struct NativeFrameRendererSelection {
    let renderer: NativeFrameRenderer
    let requestedBackend: NativeExportBackend
    let actualBackend: String
    let fallbackReason: String?
}

struct NativeExportReport: Hashable {
    let createdAt: String
    let authority: String
    let requestedBackend: NativeExportBackend
    let rendererBackend: String
    let fallbackReason: String?
    let outputPath: String
    let width: Int
    let height: Int
    let compositionWidth: Int
    let compositionHeight: Int
    let fps: Double
    let frameCount: Int
    let durationSeconds: Double
    let quality: NativeExportQuality
    let scale: NativeExportScale
    let unsupportedFXPasses: [String]
    let hardware: NativeHardwareExportReport

    func jsonObject() -> [String: Any] {
        var object: [String: Any] = [
            "createdAt": createdAt,
            "authority": authority,
            "requestedBackend": requestedBackend.rawValue,
            "rendererBackend": rendererBackend,
            "outputPath": outputPath,
            "output": [
                "width": width,
                "height": height,
                "fps": fps,
                "frameCount": frameCount,
                "durationSeconds": durationSeconds,
                "quality": quality.rawValue,
                "scale": scale.rawValue
            ],
            "composition": [
                "width": compositionWidth,
                "height": compositionHeight
            ],
            "contracts": [
                "timebase": "integer-frame-index",
                "pixelSpace": "composition-pixels-top-left",
                "visualAuthority": "UnitedGate -> canonical HyperFrame IR -> FrameDescriptor -> RenderGraph -> FXPassGraph",
                "previewExportParity": rendererBackend.contains("metal-rendergraph") ? "same-rendergraph-metal-path" : "compatibility-export-path"
            ],
            "fx": [
                "unsupportedPasses": unsupportedFXPasses
            ],
            "hardware": [
                "policy": "required-no-software-fallback",
                "metalDevice": hardware.metalDeviceName,
                "metalRegistryID": hardware.metalRegistryID,
                "videoEncoder": hardware.encoderName,
                "videoEncoderID": hardware.encoderID,
                "videoEncoderGPURegistryID": hardware.encoderGPURegistryID ?? (NSNull() as Any),
                "codec": hardware.codecName,
                "videoToolboxHardwareProbe": hardware.videoToolboxHardwareProbe
            ]
        ]
        object["fallbackReason"] = fallbackReason ?? NSNull()
        return object
    }
}

struct NativeHardwareExportReport: Hashable {
    let metalDeviceName: String
    let metalRegistryID: String
    let encoderID: String
    let encoderName: String
    let encoderGPURegistryID: String?
    let codecName: String
    let videoToolboxHardwareProbe: Bool
}
