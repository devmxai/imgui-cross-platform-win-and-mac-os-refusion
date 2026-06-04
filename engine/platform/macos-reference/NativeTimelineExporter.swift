import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import VideoToolbox

struct NativeExportProgress: Hashable, Sendable {
    let progress: Double
    let message: String
}

struct NativeTimelineExporter {
    private let workspaceURL: URL
    private let ir: HyperFrameIRBridge
    private let outputURL: URL
    private let settings: NativeExportSettings
    private let frameBridge = CanonicalHyperFrameBridge()
    private let graphCompiler = RenderGraphCompiler()
    private let fxPassGraphCompiler = FXPassGraphCompiler()

    init(workspaceURL: URL, ir: HyperFrameIRBridge, outputURL: URL, settings: NativeExportSettings) {
        self.workspaceURL = workspaceURL
        self.ir = ir
        self.outputURL = outputURL
        self.settings = settings
    }

    func export(progress: @escaping @Sendable (NativeExportProgress) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let tempVideoURL = outputURL.deletingLastPathComponent().appendingPathComponent(".makelab-video-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: tempVideoURL)
        try? FileManager.default.removeItem(at: outputURL)
        defer { try? FileManager.default.removeItem(at: tempVideoURL) }

        progress(.init(progress: 0, message: "Preparing deterministic frame export."))
        let renderResult = try await renderVideoOnly(to: tempVideoURL, progress: progress)
        progress(.init(progress: 0.92, message: "Muxing timeline audio."))
        let finalURL = try await muxAudioIfNeeded(videoURL: renderResult.url, outputURL: outputURL)
        try? FileManager.default.removeItem(at: tempVideoURL)
        try writeExportReport(result: renderResult, finalURL: finalURL)
        progress(.init(progress: 1, message: "Export complete: \(finalURL.lastPathComponent)"))
        return finalURL
    }

    private struct RenderVideoResult {
        let url: URL
        let backendName: String
        let requestedBackend: NativeExportBackend
        let fallbackReason: String?
        let width: Int
        let height: Int
        let frameCount: Int
        let unsupportedFXPasses: [String]
        let hardware: NativeHardwareExportReport
    }

    private func renderVideoOnly(to url: URL, progress: @escaping @Sendable (NativeExportProgress) -> Void) async throws -> RenderVideoResult {
        let width = settings.outputWidth(for: ir.composition)
        let height = settings.outputHeight(for: ir.composition)
        let fps = max(1, ir.fps)
        let frameCount = max(1, Int((ir.durationSeconds * fps).rounded()))
        progress(.init(progress: 0.01, message: "Requiring Metal GPU and VideoToolbox hardware encoder."))
        let hardware = try NativeHardwareExportGate.requireH264(width: width, height: height)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let bitrate = settings.bitrate(width: width, height: height, fps: fps)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoEncoderSpecificationKey: hardware.encoderSpecification,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: Int(fps.rounded())
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = false
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: attributes)
        guard writer.canAdd(input) else { throw NativeExportError.writerInputRejected }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? NativeExportError.writerStartFailed }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool else { throw NativeExportError.missingPixelBufferPool }

        let target = NativeFrameRenderTarget(
            width: width,
            height: height,
            compositionWidth: ir.composition.width,
            compositionHeight: ir.composition.height
        )
        let rendererSelection = try NativeFrameRendererFactory.makeRenderer(
            workspaceURL: workspaceURL,
            target: target,
            requestedBackend: settings.backend,
            hardware: hardware
        )
        let renderer = rendererSelection.renderer
        let fxCapabilities: PlatformFXCapabilities = .macOSNativeRuntime
        var unsupportedFXPasses = Set<String>()
        for frameIndex in 0..<frameCount {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 2_000_000)
            }
            var pixelBuffer: CVPixelBuffer?
            let createResult = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard createResult == kCVReturnSuccess, let pixelBuffer else {
                throw NativeExportError.pixelBufferAllocationFailed(createResult)
            }
            let frameTime = Double(frameIndex) / fps
            let descriptor = frameBridge.evaluate(ir: ir, timeSeconds: frameTime)
            let graph = graphCompiler.compile(descriptor: descriptor)
            let fxPassGraph = fxPassGraphCompiler.compile(renderGraph: graph, capabilities: fxCapabilities)
            for pass in fxPassGraph.unsupportedPasses {
                unsupportedFXPasses.insert("\(pass.clipId):\(pass.effectName)")
            }
            if !unsupportedFXPasses.isEmpty {
                throw NativeExportError.unsupportedFXPasses(unsupportedFXPasses.sorted())
            }
            let renderContext = NativeFrameRenderContext(
                frameIndex: frameIndex,
                time: frameTime,
                fps: fps,
                sample: { sampleTime in
                    let descriptor = frameBridge.evaluate(ir: ir, timeSeconds: sampleTime, subframe: true)
                    let graph = graphCompiler.compile(descriptor: descriptor)
                    return NativeFrameRenderSample(
                        graph: graph,
                        fxPassGraph: fxPassGraphCompiler.compile(renderGraph: graph, capabilities: fxCapabilities)
                    )
                }
            )
            try renderer.render(graph: graph, fxPassGraph: fxPassGraph, context: renderContext, into: pixelBuffer)
            let presentationTime = CMTime(seconds: Double(frameIndex) / fps, preferredTimescale: 60_000)
            guard adaptor.append(pixelBuffer, withPresentationTime: presentationTime) else {
                throw writer.error ?? NativeExportError.pixelAppendFailed(frameIndex)
            }
            if frameIndex % max(1, frameCount / 100) == 0 || frameIndex == frameCount - 1 {
                progress(.init(
                    progress: 0.02 + (Double(frameIndex + 1) / Double(frameCount)) * 0.88,
                    message: "Rendering frame \(frameIndex + 1)/\(frameCount)"
                ))
            }
        }

        input.markAsFinished()
        try await finish(writer: writer)
        return RenderVideoResult(
            url: url,
            backendName: rendererSelection.actualBackend,
            requestedBackend: rendererSelection.requestedBackend,
            fallbackReason: rendererSelection.fallbackReason,
            width: width,
            height: height,
            frameCount: frameCount,
            unsupportedFXPasses: unsupportedFXPasses.sorted(),
            hardware: NativeHardwareExportReport(
                metalDeviceName: hardware.metalDeviceName,
                metalRegistryID: Self.hex(hardware.metalRegistryID),
                encoderID: hardware.encoderID,
                encoderName: hardware.encoderName,
                encoderGPURegistryID: hardware.encoderGPURegistryID.map(Self.hex),
                codecName: hardware.codecName,
                videoToolboxHardwareProbe: true
            )
        )
    }

    private func muxAudioIfNeeded(videoURL: URL, outputURL: URL) async throws -> URL {
        let audibleLayers = ir.layers.filter { layer in
            (layer.kind == "video" || layer.kind == "audio") && !layer.muted && layer.sourceAsset != nil && layer.timing.duration > 0
        }
        guard !audibleLayers.isEmpty else {
            try FileManager.default.moveItem(at: videoURL, to: outputURL)
            return outputURL
        }

        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        guard
            let sourceVideo = try await videoAsset.loadTracks(withMediaType: .video).first,
            let targetVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else {
            throw NativeExportError.audioMuxVideoTrackMissing
        }
        let totalDuration = CMTime(seconds: ir.durationSeconds, preferredTimescale: 60_000)
        try targetVideo.insertTimeRange(CMTimeRange(start: .zero, duration: totalDuration), of: sourceVideo, at: .zero)

        var appendedAudioTracks = 0
        for layer in audibleLayers {
            guard let asset = layer.sourceAsset else { continue }
            let url = workspaceURL.appendingPathComponent(asset.path)
            let mediaAsset = AVURLAsset(url: url)
            guard let audioTrack = try await mediaAsset.loadTracks(withMediaType: .audio).first else {
                if layer.kind == "audio" { throw NativeExportError.audioMuxTrackMissing(layer.id) }
                continue
            }
            guard let targetAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw NativeExportError.audioMuxTrackMissing(layer.id)
            }
            let start = CMTime(seconds: max(0, layer.timing.start), preferredTimescale: 60_000)
            let trimIn = CMTime(seconds: max(0, layer.timing.trimIn), preferredTimescale: 60_000)
            let duration = CMTime(seconds: max(0, min(layer.timing.duration, ir.durationSeconds - layer.timing.start)), preferredTimescale: 60_000)
            guard duration > .zero else { continue }
            try targetAudio.insertTimeRange(CMTimeRange(start: trimIn, duration: duration), of: audioTrack, at: start)
            appendedAudioTracks += 1
        }

        guard appendedAudioTracks > 0 else {
            try FileManager.default.moveItem(at: videoURL, to: outputURL)
            return outputURL
        }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw NativeExportError.audioMuxSessionUnavailable
        }
        exporter.outputURL = outputURL
        exporter.outputFileType = .mp4
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export()
        if let error = exporter.error { throw error }
        return outputURL
    }

    private func finish(writer: AVAssetWriter) async throws {
        try await withCheckedThrowingContinuation { continuation in
            writer.finishWriting {
                if writer.status == .completed {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: writer.error ?? NativeExportError.writerFinishFailed)
                }
            }
        }
    }

    private func writeExportReport(result: RenderVideoResult, finalURL: URL) throws {
        let report = NativeExportReport(
            createdAt: ISO8601DateFormatter().string(from: Date()),
            authority: "UnitedGate -> canonical HyperFrame IR -> FrameDescriptor -> RenderGraph -> FXPassGraph -> NativeFrameRenderer -> MP4",
            requestedBackend: result.requestedBackend,
            rendererBackend: result.backendName,
            fallbackReason: result.fallbackReason,
            outputPath: finalURL.path,
            width: result.width,
            height: result.height,
            compositionWidth: ir.composition.width,
            compositionHeight: ir.composition.height,
            fps: ir.fps,
            frameCount: result.frameCount,
            durationSeconds: ir.durationSeconds,
            quality: settings.quality,
            scale: settings.scale,
            unsupportedFXPasses: result.unsupportedFXPasses,
            hardware: result.hardware
        )
        let data = try JSONSerialization.data(withJSONObject: report.jsonObject(), options: [.prettyPrinted, .sortedKeys])
        let reportURL = finalURL.deletingPathExtension().appendingPathExtension("export-report.json")
        try data.write(to: reportURL, options: .atomic)
    }

    private static func hex(_ value: UInt64) -> String {
        String(format: "0x%llx", value)
    }
}

final class QuartzRenderGraphFrameRenderer: NativeFrameRenderer {
    let backendName = "quartz-cgcontext-cvpixelbuffer-compatibility"
    let target: NativeFrameRenderTarget
    private let workspaceURL: URL
    private var imageCache: [String: CGImage] = [:]
    private var generatorCache: [String: AVAssetImageGenerator] = [:]

    init(workspaceURL: URL, target: NativeFrameRenderTarget) {
        self.workspaceURL = workspaceURL
        self.target = target
    }

    func render(
        graph: RenderGraphSnapshot,
        fxPassGraph: FXPassGraphSnapshot,
        context: NativeFrameRenderContext,
        into pixelBuffer: CVPixelBuffer
    ) throws {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw NativeExportError.missingPixelBufferBaseAddress
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let context = CGContext(
            data: baseAddress,
            width: target.width,
            height: target.height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw NativeExportError.contextCreationFailed
        }
        context.interpolationQuality = .high
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setFillColor(cgColor(graph.backgroundColor, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: target.width, height: target.height))
        context.scaleBy(
            x: CGFloat(target.width) / CGFloat(max(1, target.compositionWidth)),
            y: CGFloat(target.height) / CGFloat(max(1, target.compositionHeight))
        )

        for node in graph.visualNodes.sorted(by: { $0.zIndex > $1.zIndex }) {
            try draw(node: node, fxPassGraph: fxPassGraph, in: context)
        }
    }

    private func draw(node: RenderGraphNode, fxPassGraph: FXPassGraphSnapshot, in context: CGContext) throws {
        let transform = node.transform
        let rect = CGRect(x: -transform.width / 2, y: -transform.height / 2, width: transform.width, height: transform.height)
        let centerX = transform.x + transform.width / 2
        let centerY = Double(target.compositionHeight) - (transform.y + transform.height / 2)
        context.saveGState()
        context.translateBy(x: centerX, y: centerY)
        context.rotate(by: CGFloat(-transform.rotationDegrees * .pi / 180))
        context.scaleBy(x: transform.scaleX, y: transform.scaleY)
        context.setAlpha(max(0, min(1, node.opacity)))

        let radius = CGFloat(node.mask?.radius ?? node.cornerRadius.maxRadius)
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        if let shadow = node.shadow, shadow.enabled, shadow.opacity > 0 {
            context.saveGState()
            context.setShadow(
                offset: CGSize(width: shadow.offsetX, height: -shadow.offsetY),
                blur: CGFloat(max(0, shadow.blur + shadow.spread)),
                color: cgColor(shadow.color, alpha: shadow.opacity)
            )
            context.addPath(path)
            context.setFillColor(cgColor(shadow.color, alpha: 1))
            context.fillPath()
            context.restoreGState()
        }

        context.saveGState()
        context.addPath(path)
        context.clip()
        try drawContent(node: node, rect: rect, in: context)
        context.restoreGState()

        if let border = node.border, border.enabled, border.width > 0, border.opacity > 0 {
            context.saveGState()
            context.addPath(path)
            context.setStrokeColor(cgColor(border.color, alpha: border.opacity))
            context.setLineWidth(CGFloat(border.width))
            context.strokePath()
            context.restoreGState()
        }
        context.restoreGState()
    }

    private func drawContent(node: RenderGraphNode, rect: CGRect, in context: CGContext) throws {
        switch node.kind {
        case "video":
            guard let image = try videoFrame(for: node) else { return }
            draw(image: image, fit: node.clip.style.fit ?? "fill", in: rect, context: context)
        case "image":
            guard let image = try imageFrame(for: node) else { return }
            draw(image: image, fit: node.clip.style.fit ?? "fill", in: rect, context: context)
        case "shape":
            drawShape(node: node, rect: rect, context: context)
        case "text":
            drawText(node: node, rect: rect, context: context)
        default:
            let fill = node.fill ?? RenderFill(enabled: true, color: "#FFFFFF", opacity: 0.2)
            context.setFillColor(cgColor(fill.color, alpha: fill.opacity))
            context.fill(rect)
        }
    }

    private func draw(image: CGImage, fit: String, in rect: CGRect, context: CGContext) {
        let imageAspect = CGFloat(image.width) / max(1, CGFloat(image.height))
        let rectAspect = rect.width / max(1, rect.height)
        let scale: CGFloat
        if fit == "contain" {
            scale = imageAspect > rectAspect ? rect.width / CGFloat(image.width) : rect.height / CGFloat(image.height)
        } else {
            scale = imageAspect > rectAspect ? rect.height / CGFloat(image.height) : rect.width / CGFloat(image.width)
        }
        let drawSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let drawRect = CGRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        context.draw(image, in: drawRect)
    }

    private func drawShape(node: RenderGraphNode, rect: CGRect, context: CGContext) {
        let fill = node.fill ?? RenderFill(enabled: true, color: "#16A34A", opacity: 1)
        context.setFillColor(cgColor(fill.color, alpha: fill.opacity))
        switch node.clip.shape?.kind {
        case "circle":
            context.fillEllipse(in: rect)
        case "line":
            let y = rect.midY
            context.setStrokeColor(cgColor(fill.color, alpha: fill.opacity))
            context.setLineWidth(max(2, rect.height))
            context.move(to: CGPoint(x: rect.minX, y: y))
            context.addLine(to: CGPoint(x: rect.maxX, y: y))
            context.strokePath()
        default:
            context.fill(rect)
        }
    }

    private func drawText(node: RenderGraphNode, rect: CGRect, context: CGContext) {
        let text = node.clip.text?.content ?? node.clip.name
        let size = max(1, node.clip.text?.fontSize ?? 48)
        let color = NSColor(cgColor: cgColor(node.clip.text?.color ?? "#111827", alpha: node.opacity)) ?? .labelColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment(node.clip.text?.align)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: CGFloat(size), weight: .bold),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        NSString(string: text).draw(in: rect, withAttributes: attributes)
    }

    private func videoFrame(for node: RenderGraphNode) throws -> CGImage? {
        guard let asset = node.asset else { return nil }
        let generator = try generator(for: asset)
        let time = CMTime(seconds: max(0, node.mediaTime), preferredTimescale: 60_000)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try generator.copyCGImage(at: time, actualTime: nil)
    }

    private func imageFrame(for node: RenderGraphNode) throws -> CGImage? {
        guard let asset = node.asset else { return nil }
        if let cached = imageCache[asset.id] { return cached }
        let url = workspaceURL.appendingPathComponent(asset.path)
        guard let image = NSImage(contentsOf: url), let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        imageCache[asset.id] = cgImage
        return cgImage
    }

    private func generator(for asset: WorkspaceAsset) throws -> AVAssetImageGenerator {
        if let cached = generatorCache[asset.id] { return cached }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: workspaceURL.appendingPathComponent(asset.path)))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: max(target.width, asset.width ?? 0), height: max(target.height, asset.height ?? 0))
        generatorCache[asset.id] = generator
        return generator
    }

    private func textAlignment(_ value: String?) -> NSTextAlignment {
        switch value {
        case "left": return .left
        case "right": return .right
        default: return .center
        }
    }
}

enum NativeExportError: LocalizedError {
    case writerInputRejected
    case writerStartFailed
    case writerFinishFailed
    case missingPixelBufferPool
    case pixelBufferAllocationFailed(CVReturn)
    case pixelAppendFailed(Int)
    case missingPixelBufferBaseAddress
    case contextCreationFailed
    case hardwareMetalDeviceUnavailable
    case hardwareVideoEncoderUnavailable(codec: String)
    case hardwareEncoderEnumerationFailed(OSStatus)
    case hardwareEncoderNotAssociatedWithMetalDevice
    case hardwareEncoderProbeFailed(OSStatus)
    case hardwareEncoderProofRejected(OSStatus)
    case hardwareMetalRendererInitializationFailed(String)
    case unsupportedFXPasses([String])
    case audioMuxVideoTrackMissing
    case audioMuxTrackMissing(String)
    case audioMuxSessionUnavailable

    var errorDescription: String? {
        switch self {
        case .writerInputRejected:
            return "Native export writer rejected the video input."
        case .writerStartFailed:
            return "Native export writer could not start."
        case .writerFinishFailed:
            return "Native export writer did not finish successfully."
        case .missingPixelBufferPool:
            return "Native export writer did not provide a CVPixelBuffer pool."
        case .pixelBufferAllocationFailed(let code):
            return "Native export could not allocate a CVPixelBuffer (\(code))."
        case .pixelAppendFailed(let frameIndex):
            return "Native export could not append frame \(frameIndex)."
        case .missingPixelBufferBaseAddress:
            return "Native export pixel buffer has no writable base address."
        case .contextCreationFailed:
            return "Native export could not create an offscreen frame context."
        case .hardwareMetalDeviceUnavailable:
            return "Export blocked: no physical Metal GPU is available."
        case .hardwareVideoEncoderUnavailable(let codec):
            return "Export blocked: no VideoToolbox hardware encoder is available for \(codec)."
        case .hardwareEncoderEnumerationFailed(let status):
            return "Export blocked: VideoToolbox could not enumerate hardware encoders (\(status))."
        case .hardwareEncoderNotAssociatedWithMetalDevice:
            return "Export blocked: no hardware video encoder is compatible with an available Metal GPU."
        case .hardwareEncoderProbeFailed(let status):
            return "Export blocked: VideoToolbox refused the required hardware encoder session (\(status))."
        case .hardwareEncoderProofRejected(let status):
            return "Export blocked: VideoToolbox did not prove hardware acceleration (\(status))."
        case .hardwareMetalRendererInitializationFailed(let name):
            return "Export blocked: Metal renderer could not initialize on \(name)."
        case .unsupportedFXPasses(let passes):
            return "Export blocked: Metal export does not support these FX passes yet: \(passes.joined(separator: ", "))."
        case .audioMuxVideoTrackMissing:
            return "Export blocked: the hardware-rendered MP4 has no video track for audio muxing."
        case .audioMuxTrackMissing(let layerID):
            return "Export blocked: timeline audio layer \(layerID) could not provide an audio track."
        case .audioMuxSessionUnavailable:
            return "Export blocked: native passthrough audio muxing is unavailable."
        }
    }
}

private func cgColor(_ hex: String, alpha: Double) -> CGColor {
    let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    let value = UInt64(clean, radix: 16) ?? 0xffffff
    let r = CGFloat((value >> 16) & 0xff) / 255.0
    let g = CGFloat((value >> 8) & 0xff) / 255.0
    let b = CGFloat(value & 0xff) / 255.0
    return CGColor(red: r, green: g, blue: b, alpha: CGFloat(max(0, min(1, alpha))))
}
