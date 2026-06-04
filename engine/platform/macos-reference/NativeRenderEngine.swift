import AppKit
import AVFoundation
import Combine
import CoreText
import CoreVideo
import Metal
import MetalKit

final class NativeRenderEngine: NSObject, ObservableObject, MTKViewDelegate {
    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var textureCache: CVMetalTextureCache?
    private var textureLoader: MTKTextureLoader?
    private var backgroundPipeline: MTLRenderPipelineState?
    private var texturePipeline: MTLRenderPipelineState?
    private var additiveTexturePipeline: MTLRenderPipelineState?
    private var additiveFloatTexturePipeline: MTLRenderPipelineState?
    private var shapePipeline: MTLRenderPipelineState?
    private var fxRuntime: MetalFXRuntime?

    private let frameBridge = CanonicalHyperFrameBridge()
    private let graphCompiler = RenderGraphCompiler()
    private let fxCompiler = FXPassGraphCompiler()

    private var workspaceURL: URL?
    private var ir: HyperFrameIRBridge?
    private var viewportSize: CGSize = .zero
    private var isPlaying = false
    private var isLiveScrubbing = false
    private var startFrameIndex = 0
    private var seekFrameIndex = 0
    private var playStartHostTime = CACurrentMediaTime()
    private var lastPublishedFrame = -1
    private var lastPublishHostTime = 0.0
    private var cachedFrame: NativeCachedFrame?
    private var timelineObserver: ((Int) -> Void)?
    private weak var renderView: MTKView?

    private var videoProviders: [String: RealtimeVideoSourceProvider] = [:]
    private var imageTextures: [String: MTLTexture] = [:]
    private var textTextures: [String: MTLTexture] = [:]
    private var shadowTextures: [String: MTLTexture] = [:]

    @MainActor
    func attach(to view: MTKView) {
        guard let device = view.device else { return }
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        self.textureLoader = MTKTextureLoader(device: device)
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        backgroundPipeline = Self.makeBackgroundPipeline(device: device, pixelFormat: view.colorPixelFormat)
        texturePipeline = Self.makeTexturePipeline(device: device, pixelFormat: view.colorPixelFormat)
        additiveTexturePipeline = Self.makeAdditiveTexturePipeline(device: device, pixelFormat: view.colorPixelFormat)
        additiveFloatTexturePipeline = Self.makeAdditiveTexturePipeline(device: device, pixelFormat: .rgba16Float)
        shapePipeline = Self.makeShapePipeline(device: device, pixelFormat: view.colorPixelFormat)
        fxRuntime = MetalFXRuntime(device: device)
        renderView = view
        view.delegate = self
    }

    @MainActor
    func loadProject(_ ir: HyperFrameIRBridge?, workspaceURL: URL?, displayFrame: Int? = nil) {
        let projectChanged = self.ir?.revision != ir?.revision || self.workspaceURL != workspaceURL
        if projectChanged {
            cachedFrame = nil
            imageTextures.removeAll()
            textTextures.removeAll()
            shadowTextures.removeAll()
            videoProviders.removeAll()
        }
        self.ir = ir
        self.workspaceURL = workspaceURL
        if projectChanged, let displayFrame {
            seekFrameIndex = max(0, displayFrame)
            renderCurrentFrame(forcePublish: false)
        }
    }

    @MainActor
    func refreshProject(_ ir: HyperFrameIRBridge?, workspaceURL: URL?, displayFrame: Int) {
        cachedFrame = nil
        imageTextures.removeAll()
        textTextures.removeAll()
        shadowTextures.removeAll()
        videoProviders.removeAll()
        self.ir = ir
        self.workspaceURL = workspaceURL
        seekFrameIndex = max(0, displayFrame)
        if isPlaying {
            startFrameIndex = seekFrameIndex
            playStartHostTime = CACurrentMediaTime()
        }
        renderCurrentFrame(forcePublish: true)
    }

    @MainActor
    func setViewportSize(_ size: CGSize) {
        viewportSize = size
        if !isPlaying {
            renderCurrentFrame(forcePublish: false)
        }
    }

    func setTimelineObserver(_ observer: @escaping (Int) -> Void) {
        timelineObserver = observer
    }

    @MainActor
    func play(from frameIndex: Int) {
        guard !isPlaying else { return }
        isLiveScrubbing = false
        startFrameIndex = frameIndex
        seekFrameIndex = frameIndex
        playStartHostTime = CACurrentMediaTime()
        isPlaying = true
        renderView?.isPaused = false
        syncVideoProviders(frameIndex: frameIndex, play: true)
    }

    @MainActor
    func pause() {
        guard isPlaying else { return }
        seekFrameIndex = currentFrameIndex()
        isPlaying = false
        syncVideoProviders(frameIndex: seekFrameIndex, play: false)
        renderView?.isPaused = true
        renderCurrentFrame(forcePublish: false)
    }

    @MainActor
    func seek(to frameIndex: Int) {
        guard !isPlaying else { return }
        isLiveScrubbing = false
        seekFrameIndex = max(0, frameIndex)
        syncVideoProviders(frameIndex: seekFrameIndex, play: false)
        renderView?.isPaused = true
        renderCurrentFrame(forcePublish: false)
    }

    @MainActor
    func beginScrub(to frameIndex: Int) {
        isLiveScrubbing = true
        scrub(to: frameIndex)
    }

    @MainActor
    func scrub(to frameIndex: Int) {
        if isPlaying {
            isPlaying = false
            pauseVideoProviders()
        }
        seekFrameIndex = max(0, frameIndex)
        renderView?.isPaused = true
        renderCurrentFrame(forcePublish: false)
    }

    @MainActor
    func endScrub(to frameIndex: Int) {
        isLiveScrubbing = false
        seek(to: frameIndex)
    }

    @MainActor
    func renderCurrentFrame(forcePublish: Bool = true) {
        renderView?.draw()
        publishFrameIfNeeded(currentFrameIndex(), force: forcePublish)
    }

    func renderOffscreen(frameIndex: Int, target: NativeFrameRenderTarget) throws -> CVPixelBuffer {
        throw NativeExportError.contextCreationFailed
    }

    @MainActor
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = size
    }

    @MainActor
    func draw(in view: MTKView) {
        guard
            let ir,
            let commandQueue,
            let renderPassDescriptor = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else {
            return
        }

        let frameIndex = currentFrameIndex()
        let frame = evaluatedFrame(ir: ir, frameIndex: frameIndex)
        let graph = frame.graph
        let fxGraph = frame.fxGraph
        let resolvedNodes = resolveNodes(graph: graph, fxGraph: fxGraph, commandBuffer: commandBuffer)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }
        drawBackground(graph: graph, encoder: encoder)
        for resolvedNode in resolvedNodes {
            drawNode(resolvedNode, graph: graph, fxGraph: fxGraph, encoder: encoder)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        publishFrameIfNeeded(frameIndex, force: false)
    }

    @MainActor
    private func currentFrameIndex() -> Int {
        guard let ir else { return seekFrameIndex }
        guard isPlaying else { return min(max(0, seekFrameIndex), max(0, Int((ir.durationSeconds * ir.fps).rounded()) - 1)) }
        let elapsed = max(0, CACurrentMediaTime() - playStartHostTime)
        let frame = startFrameIndex + Int((elapsed * max(1, ir.fps)).rounded(.down))
        let last = max(0, Int((ir.durationSeconds * ir.fps).rounded()) - 1)
        if frame >= last {
            isPlaying = false
            syncVideoProviders(frameIndex: last, play: false)
            renderView?.isPaused = true
            return last
        }
        return max(0, frame)
    }

    private func publishFrameIfNeeded(_ frameIndex: Int, force: Bool) {
        let now = CACurrentMediaTime()
        guard force || frameIndex != lastPublishedFrame, force || now - lastPublishHostTime >= 1.0 / 15.0 else { return }
        lastPublishedFrame = frameIndex
        lastPublishHostTime = now
        timelineObserver?(frameIndex)
    }

    private func evaluatedFrame(ir: HyperFrameIRBridge, frameIndex: Int) -> NativeCachedFrame {
        if let cachedFrame, cachedFrame.frameIndex == frameIndex, cachedFrame.revision == ir.revision {
            return cachedFrame
        }
        let descriptor = frameBridge.evaluate(ir: ir, frameIndex: frameIndex)
        let graph = graphCompiler.compile(descriptor: descriptor)
        let fxGraph = fxCompiler.compile(renderGraph: graph, capabilities: .macOSNativeRuntime)
        let frame = NativeCachedFrame(
            revision: ir.revision,
            frameIndex: frameIndex,
            graph: graph,
            fxGraph: fxGraph
        )
        cachedFrame = frame
        return frame
    }

    private func resolveNodes(
        graph: RenderGraphSnapshot,
        fxGraph: FXPassGraphSnapshot,
        commandBuffer: MTLCommandBuffer
    ) -> [NativeResolvedNode] {
        graph.visualNodes
            .sorted { $0.zIndex < $1.zIndex }
            .map { node in
                guard let sourceTexture = sourceTexture(for: node, frameIndex: graph.frameIndex, fps: graph.fps) else {
                    return NativeResolvedNode(node: node, compositeStyleNode: node, texture: nil, boundsScaleX: 1, boundsScaleY: 1)
                }
                if let motionBlurPass = motionBlurPass(for: node, fxGraph: fxGraph),
                   let blurredTexture = renderMotionBlurTexture(
                    node: node,
                    graph: graph,
                    pass: motionBlurPass,
                    commandBuffer: commandBuffer
                ) {
                    let fullscreenNode = fullscreenTextureNode(from: node, graph: graph)
                    let postTemporal = fxRuntime?.resolve(
                        sourceTexture: blurredTexture,
                        node: fullscreenNode,
                        fxGraph: fxGraph,
                        commandBuffer: commandBuffer,
                        isLiveScrubbing: isRealtimeInteraction,
                        includePreTransform: false
                    ) ?? MetalFXResolvedTexture(texture: blurredTexture, boundsScaleX: 1, boundsScaleY: 1)
                    return NativeResolvedNode(
                        node: fullscreenNode,
                        compositeStyleNode: node,
                        texture: postTemporal.texture,
                        boundsScaleX: 1,
                        boundsScaleY: 1
                    )
                }
                let resolved = fxRuntime?.resolve(
                    sourceTexture: sourceTexture,
                    node: node,
                    fxGraph: fxGraph,
                    commandBuffer: commandBuffer,
                    isLiveScrubbing: isRealtimeInteraction
                ) ?? MetalFXResolvedTexture(texture: sourceTexture, boundsScaleX: 1, boundsScaleY: 1)
                return NativeResolvedNode(
                    node: node,
                    compositeStyleNode: node,
                    texture: resolved.texture,
                    boundsScaleX: resolved.boundsScaleX,
                    boundsScaleY: resolved.boundsScaleY
                )
            }
    }

    private func motionBlurPass(for node: RenderGraphNode, fxGraph: FXPassGraphSnapshot) -> FXPassNode? {
        fxGraph.passes.first {
            $0.clipId == node.clipId &&
            $0.effectName == "motionBlur" &&
            $0.status == .supported &&
            $0.category == .temporal
        }
    }

    private func renderMotionBlurTexture(
        node: RenderGraphNode,
        graph: RenderGraphSnapshot,
        pass: FXPassNode,
        commandBuffer: MTLCommandBuffer
    ) -> MTLTexture? {
        guard let ir, let additiveFloatTexturePipeline else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: max(1, graph.width),
            height: max(1, graph.height),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        guard let device, let accumulationTexture = device.makeTexture(descriptor: descriptor) else { return nil }

        let samplePlan = MotionBlurQualityPlanner.plan(
            pass: pass,
            node: node,
            frameTime: graph.time,
            fps: graph.fps,
            maxSamples: motionBlurSampleBudget(),
            nodeAtTime: { sampleTime in
                let descriptor = frameBridge.evaluate(ir: ir, timeSeconds: sampleTime, subframe: true)
                return graphCompiler.compile(descriptor: descriptor).visualNodes.first(where: { $0.clipId == node.clipId })
            }
        )
        var resolvedSamples: [(node: RenderGraphNode, texture: MTLTexture, boundsScaleX: Double, boundsScaleY: Double, weight: Double)] = []
        for sample in samplePlan.samples {
            let descriptor = frameBridge.evaluate(ir: ir, timeSeconds: sample.time, subframe: true)
            let sampleGraph = graphCompiler.compile(descriptor: descriptor)
            guard let sampleNode = sampleGraph.visualNodes.first(where: { $0.clipId == node.clipId }) else { continue }
            let sampleFrameIndex = max(0, Int((sample.time * graph.fps).rounded()))
            guard let sampleTexture = sourceTexture(for: sampleNode, frameIndex: sampleFrameIndex, fps: graph.fps) else { continue }
            let sampleFxGraph = fxCompiler.compile(renderGraph: sampleGraph, capabilities: .macOSNativeRuntime)
            let sampleResolved = fxRuntime?.resolve(
                sourceTexture: sampleTexture,
                node: sampleNode,
                fxGraph: sampleFxGraph,
                commandBuffer: commandBuffer,
                isLiveScrubbing: isRealtimeInteraction,
                includePostTransform: false
            ) ?? MetalFXResolvedTexture(texture: sampleTexture, boundsScaleX: 1, boundsScaleY: 1)
            resolvedSamples.append((
                node: sampleNode,
                texture: sampleResolved.texture,
                boundsScaleX: sampleResolved.boundsScaleX,
                boundsScaleY: sampleResolved.boundsScaleY,
                weight: sample.weight
            ))
        }
        guard !resolvedSamples.isEmpty else { return nil }

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = accumulationTexture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else { return nil }
        for sample in resolvedSamples {
            drawTexture(
                sample.texture,
                node: sample.node,
                graph: graph,
                boundsScaleX: sample.boundsScaleX,
                boundsScaleY: sample.boundsScaleY,
                opacityScale: sample.weight,
                pipeline: additiveFloatTexturePipeline,
                encoder: encoder
            )
        }
        encoder.endEncoding()
        return accumulationTexture
    }

    private func fullscreenTextureNode(from node: RenderGraphNode, graph: RenderGraphSnapshot) -> RenderGraphNode {
        let transform = RenderTransform(
            x: 0,
            y: 0,
            width: Double(graph.width),
            height: Double(graph.height),
            anchorX: 0,
            anchorY: 0,
            scaleX: 1,
            scaleY: 1,
            rotationDegrees: 0,
            skewXDegrees: 0,
            skewYDegrees: 0
        )
        return RenderGraphNode(
            id: "\(node.id):motionBlurIsolation",
            clipId: node.clipId,
            trackId: node.trackId,
            kind: node.kind,
            zIndex: node.zIndex,
            clip: node.clip,
            asset: node.asset,
            localTime: node.localTime,
            mediaTime: node.mediaTime,
            transform: transform,
            opacity: 1,
            fill: nil,
            cornerRadius: RenderCornerRadius(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            border: nil,
            shadow: nil,
            mask: nil,
            effects: [],
            rawEffects: nil,
            rawStyle: node.rawStyle
        )
    }

    private func drawBackground(graph: RenderGraphSnapshot, encoder: MTLRenderCommandEncoder) {
        guard let backgroundPipeline else { return }
        var uniforms = NativeBackgroundUniforms(color: rgbaFloat4(graph.backgroundColor))
        encoder.setRenderPipelineState(backgroundPipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<NativeBackgroundUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<NativeBackgroundUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }

    private func drawNode(
        _ resolvedNode: NativeResolvedNode,
        graph: RenderGraphSnapshot,
        fxGraph: FXPassGraphSnapshot,
        encoder: MTLRenderCommandEncoder
    ) {
        let node = resolvedNode.node
        let compositeStyleNode = resolvedNode.compositeStyleNode ?? node
        if let shadow = compositeStyleNode.shadow, shadow.enabled, shadow.opacity > 0 {
            drawShadow(compositeStyleNode, shadow: shadow, graph: graph, encoder: encoder)
        }

        switch node.kind {
        case "video", "image", "text":
            if let texture = resolvedNode.texture {
                drawTexture(
                    texture,
                    node: node,
                    graph: graph,
                    boundsScaleX: resolvedNode.boundsScaleX,
                    boundsScaleY: resolvedNode.boundsScaleY,
                    encoder: encoder
                )
            }
        case "shape":
            drawShape(node, graph: graph, encoder: encoder, mode: .fill)
        default:
            drawShape(node, graph: graph, encoder: encoder, mode: .fill)
        }

        if let border = compositeStyleNode.border, border.enabled, border.width > 0, border.opacity > 0 {
            drawBorder(compositeStyleNode, border: border, graph: graph, encoder: encoder)
        }

        if !fxGraph.unsupportedPasses.isEmpty {
            // Diagnostics are emitted through FXPassGraph reports; the engine never fakes unsupported FX.
        }
    }

    private func drawTexture(
        _ texture: MTLTexture,
        node: RenderGraphNode,
        graph: RenderGraphSnapshot,
        boundsScaleX: Double = 1,
        boundsScaleY: Double = 1,
        opacityScale: Double = 1,
        pipeline: MTLRenderPipelineState? = nil,
        encoder: MTLRenderCommandEncoder
    ) {
        guard let pipeline = pipeline ?? texturePipeline else { return }
        let drawNode = scaledNode(node, boundsScaleX: boundsScaleX, boundsScaleY: boundsScaleY)
        var vertices = quadVertices(for: drawNode, graph: graph)
        var uniforms = NativeLayerUniforms(
            color: SIMD4<Float>(1, 1, 1, Float(node.opacity * opacityScale)),
            size: SIMD2<Float>(Float(drawNode.transform.width), Float(drawNode.transform.height)),
            radius: Float(node.mask?.radius ?? node.cornerRadius.maxRadius),
            opacity: Float(node.opacity * opacityScale),
            mode: 0
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<NativeRenderVertex>.stride * vertices.count, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<NativeLayerUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    private func drawShape(
        _ node: RenderGraphNode,
        graph: RenderGraphSnapshot,
        encoder: MTLRenderCommandEncoder,
        mode: NativeShapeMode
    ) {
        guard let shapePipeline else { return }
        var vertices = quadVertices(for: node, graph: graph)
        var uniforms = NativeLayerUniforms(
            color: fillColor(for: node),
            size: SIMD2<Float>(Float(node.transform.width), Float(node.transform.height)),
            radius: Float(node.mask?.radius ?? node.cornerRadius.maxRadius),
            opacity: Float(node.opacity),
            mode: Float(mode.rawValue)
        )
        encoder.setRenderPipelineState(shapePipeline)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<NativeRenderVertex>.stride * vertices.count, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<NativeLayerUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    private func drawBorder(
        _ node: RenderGraphNode,
        border: RenderBorder,
        graph: RenderGraphSnapshot,
        encoder: MTLRenderCommandEncoder
    ) {
        guard let shapePipeline else { return }
        var vertices = quadVertices(for: node, graph: graph)
        var color = rgbaFloat4(border.color)
        color.w *= Float(border.opacity)
        var uniforms = NativeLayerUniforms(
            color: color,
            size: SIMD2<Float>(Float(node.transform.width), Float(node.transform.height)),
            radius: Float(node.mask?.radius ?? node.cornerRadius.maxRadius),
            opacity: Float(node.opacity),
            mode: Float(NativeShapeMode.border.rawValue + Int(max(1, border.width)) * 10)
        )
        encoder.setRenderPipelineState(shapePipeline)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<NativeRenderVertex>.stride * vertices.count, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<NativeLayerUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    private func drawShadow(
        _ node: RenderGraphNode,
        shadow: RenderShadow,
        graph: RenderGraphSnapshot,
        encoder: MTLRenderCommandEncoder
    ) {
        guard let shapePipeline else { return }
        if let texture = shadowTexture(for: node, shadow: shadow) {
            let pad = max(1, ceil(shadow.blur * 2 + abs(shadow.spread)))
            let shadowTransform = RenderTransform(
                x: node.transform.x + shadow.offsetX - pad - shadow.spread,
                y: node.transform.y + shadow.offsetY - pad - shadow.spread,
                width: node.transform.width + pad * 2 + shadow.spread * 2,
                height: node.transform.height + pad * 2 + shadow.spread * 2,
                anchorX: node.transform.anchorX,
                anchorY: node.transform.anchorY,
                scaleX: node.transform.scaleX,
                scaleY: node.transform.scaleY,
                rotationDegrees: node.transform.rotationDegrees,
                skewXDegrees: node.transform.skewXDegrees,
                skewYDegrees: node.transform.skewYDegrees
            )
            drawTexture(
                texture,
                node: shadowTextureNode(
                    from: node,
                    transform: shadowTransform,
                    opacity: shadow.opacity * node.opacity
                ),
                graph: graph,
                encoder: encoder
            )
            return
        }
        var shadowNode = node
        let offset = RenderTransform(
            x: node.transform.x + shadow.offsetX,
            y: node.transform.y + shadow.offsetY,
            width: node.transform.width + shadow.spread * 2,
            height: node.transform.height + shadow.spread * 2,
            anchorX: node.transform.anchorX,
            anchorY: node.transform.anchorY,
            scaleX: node.transform.scaleX,
            scaleY: node.transform.scaleY,
            rotationDegrees: node.transform.rotationDegrees,
            skewXDegrees: node.transform.skewXDegrees,
            skewYDegrees: node.transform.skewYDegrees
        )
        shadowNode = RenderGraphNode(
            id: node.id,
            clipId: node.clipId,
            trackId: node.trackId,
            kind: node.kind,
            zIndex: node.zIndex,
            clip: node.clip,
            asset: node.asset,
            localTime: node.localTime,
            mediaTime: node.mediaTime,
            transform: offset,
            opacity: node.opacity,
            fill: node.fill,
            cornerRadius: node.cornerRadius,
            border: node.border,
            shadow: node.shadow,
            mask: node.mask,
            effects: node.effects,
            rawEffects: node.rawEffects,
            rawStyle: node.rawStyle
        )
        var vertices = quadVertices(for: shadowNode, graph: graph)
        var color = rgbaFloat4(shadow.color)
        color.w *= Float(shadow.opacity)
        var uniforms = NativeLayerUniforms(
            color: color,
            size: SIMD2<Float>(Float(shadowNode.transform.width), Float(shadowNode.transform.height)),
            radius: Float(node.mask?.radius ?? node.cornerRadius.maxRadius),
            opacity: Float(node.opacity),
            mode: Float(NativeShapeMode.fill.rawValue)
        )
        encoder.setRenderPipelineState(shapePipeline)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<NativeRenderVertex>.stride * vertices.count, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<NativeLayerUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    private func shadowTexture(for node: RenderGraphNode, shadow: RenderShadow) -> MTLTexture? {
        guard let textureLoader else { return nil }
        let pad = max(1, ceil(shadow.blur * 2 + abs(shadow.spread)))
        let width = max(1, Int((node.transform.width + pad * 2 + shadow.spread * 2).rounded(.up)))
        let height = max(1, Int((node.transform.height + pad * 2 + shadow.spread * 2).rounded(.up)))
        let radius = max(0, node.mask?.radius ?? node.cornerRadius.maxRadius) + max(0, shadow.spread)
        let key = [
            node.clipId,
            "\(width)x\(height)",
            String(format: "%.3f", radius),
            String(format: "%.3f", shadow.blur),
            String(format: "%.3f", shadow.spread),
            shadow.color
        ].joined(separator: "|")
        if let cached = shadowTextures[key] { return cached }
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        let casterOffset = CGFloat(width * 2)
        let rect = CGRect(
            x: CGFloat(pad) - casterOffset,
            y: pad,
            width: max(1, node.transform.width + shadow.spread * 2),
            height: max(1, node.transform.height + shadow.spread * 2)
        )
        context.setShadow(
            offset: CGSize(width: casterOffset, height: 0),
            blur: CGFloat(max(0, shadow.blur)),
            color: NSColor(hexString: shadow.color)
                .withAlphaComponent(1)
                .cgColor
        )
        context.setFillColor(NSColor.black.cgColor)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()
        guard let cgImage = context.makeImage() else { return nil }
        let texture = try? textureLoader.newTexture(cgImage: cgImage, options: [MTKTextureLoader.Option.SRGB: false])
        if let texture {
            if shadowTextures.count >= 128 { shadowTextures.removeAll(keepingCapacity: true) }
            shadowTextures[key] = texture
        }
        return texture
    }

    private func shadowTextureNode(from node: RenderGraphNode, transform: RenderTransform, opacity: Double) -> RenderGraphNode {
        RenderGraphNode(
            id: "\(node.id):shadowTexture",
            clipId: node.clipId,
            trackId: node.trackId,
            kind: "image",
            zIndex: node.zIndex,
            clip: node.clip,
            asset: nil,
            localTime: node.localTime,
            mediaTime: node.mediaTime,
            transform: transform,
            opacity: opacity,
            fill: nil,
            cornerRadius: RenderCornerRadius(topLeft: 0, topRight: 0, bottomRight: 0, bottomLeft: 0),
            border: nil,
            shadow: nil,
            mask: nil,
            effects: [],
            rawEffects: nil,
            rawStyle: [:]
        )
    }

    private func fillColor(for node: RenderGraphNode) -> SIMD4<Float> {
        let fill = node.fill
        var color = rgbaFloat4(fill?.color ?? node.clip.style.fill?.color ?? "#FFFFFF")
        color.w *= Float(fill?.opacity ?? node.clip.style.fill?.opacity ?? 1)
        return color
    }

    private func sourceTexture(for node: RenderGraphNode, frameIndex: Int, fps: Double) -> MTLTexture? {
        switch node.kind {
        case "video":
            return videoTexture(for: node, frameIndex: frameIndex, fps: fps)
        case "image":
            return imageTexture(for: node)
        case "text":
            return textTexture(for: node)
        default:
            return nil
        }
    }

    private func scaledNode(_ node: RenderGraphNode, boundsScaleX: Double, boundsScaleY: Double) -> RenderGraphNode {
        guard abs(boundsScaleX - 1) > 0.0001 || abs(boundsScaleY - 1) > 0.0001 else { return node }
        let transform = node.transform
        let centerX = transform.x + transform.width * transform.anchorX
        let centerY = transform.y + transform.height * transform.anchorY
        let width = transform.width * boundsScaleX
        let height = transform.height * boundsScaleY
        let scaledTransform = RenderTransform(
            x: centerX - width * transform.anchorX,
            y: centerY - height * transform.anchorY,
            width: width,
            height: height,
            anchorX: transform.anchorX,
            anchorY: transform.anchorY,
            scaleX: transform.scaleX,
            scaleY: transform.scaleY,
            rotationDegrees: transform.rotationDegrees,
            skewXDegrees: transform.skewXDegrees,
            skewYDegrees: transform.skewYDegrees
        )
        return RenderGraphNode(
            id: node.id,
            clipId: node.clipId,
            trackId: node.trackId,
            kind: node.kind,
            zIndex: node.zIndex,
            clip: node.clip,
            asset: node.asset,
            localTime: node.localTime,
            mediaTime: node.mediaTime,
            transform: scaledTransform,
            opacity: node.opacity,
            fill: node.fill,
            cornerRadius: node.cornerRadius,
            border: node.border,
            shadow: node.shadow,
            mask: node.mask,
            effects: node.effects,
            rawEffects: node.rawEffects,
            rawStyle: node.rawStyle
        )
    }

    private func videoTexture(for node: RenderGraphNode, frameIndex: Int, fps: Double) -> MTLTexture? {
        guard
            let workspaceURL,
            let asset = node.asset,
            let textureCache
        else { return nil }
        let url = workspaceURL.appendingPathComponent(asset.path)
        let provider = videoProviders[node.clipId] ?? RealtimeVideoSourceProvider(url: url)
        videoProviders[node.clipId] = provider
        if isLiveScrubbing {
            provider.scrub(mediaTime: node.mediaTime)
        } else {
            provider.sync(mediaTime: node.mediaTime, playing: isPlaying)
        }
        return provider.texture(textureCache: textureCache)
    }

    private func imageTexture(for node: RenderGraphNode) -> MTLTexture? {
        guard
            let workspaceURL,
            let asset = node.asset,
            let textureLoader
        else { return nil }
        let key = asset.id
        if let cached = imageTextures[key] { return cached }
        let url = workspaceURL.appendingPathComponent(asset.path)
        guard
            let image = NSImage(contentsOf: url),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let texture = try? textureLoader.newTexture(cgImage: cgImage, options: [
            MTKTextureLoader.Option.SRGB: false
        ])
        if let texture { imageTextures[key] = texture }
        return texture
    }

    private func textTexture(for node: RenderGraphNode) -> MTLTexture? {
        guard let textureLoader else { return nil }
        let content = node.clip.text?.content ?? "Text"
        let text = node.clip.text
        let key = "\(node.clipId)|\(content)|\(text?.fontFamily ?? "")|\(text?.fontWeight ?? "")|\(text?.fontSize ?? 48)|\(text?.color ?? "#111827")|\(Int(node.transform.width))x\(Int(node.transform.height))|\(text?.extra ?? [:])|\(node.rawStyle)"
        if let cached = textTextures[key] { return cached }
        let width = max(1, Int(node.transform.width.rounded()))
        let height = max(1, Int(node.transform.height.rounded()))
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            )
        else { return nil }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let textTransform = text?.extra["textTransform"]?.stringValue ?? "none"
        let renderedContent = transformedText(content, transform: textTransform)
        let fontSize = max(1, CGFloat(text?.fontSize ?? 48))
        let lineHeight = max(fontSize, CGFloat(text?.extra["lineHeight"]?.numberValue ?? Double(fontSize)))
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment(text?.align)
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        let font = resolvedFont(family: text?.fontFamily, size: fontSize, weight: text?.fontWeight)
        let shadow = text?.extra["shadow"]?.objectValue
        if shadow?["enabled"]?.boolValue == true {
            context.setShadow(
                offset: CGSize(
                    width: CGFloat(shadow?["x"]?.numberValue ?? 0),
                    height: CGFloat(-(shadow?["y"]?.numberValue ?? 0))
                ),
                blur: CGFloat(max(0, shadow?["blur"]?.numberValue ?? 0)),
                color: NSColor(hexString: shadow?["color"]?.stringValue ?? "#000000")
                    .withAlphaComponent(CGFloat(shadow?["opacity"]?.numberValue ?? 1))
                    .cgColor
            )
        }
        let stroke = text?.extra["stroke"]?.objectValue
        let strokeWidthPixels = stroke?["enabled"]?.boolValue == true
            ? CGFloat(stroke?["width"]?.numberValue ?? 0)
            : 0
        let strokeWidthPercent = strokeWidthPixels > 0
            ? -100 * strokeWidthPixels / fontSize
            : 0
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(hexString: text?.color ?? "#111827"),
            .paragraphStyle: paragraph,
            .kern: CGFloat(text?.extra["letterSpacing"]?.numberValue ?? 0),
            .strokeColor: NSColor(hexString: stroke?["color"]?.stringValue ?? text?.color ?? "#111827")
                .withAlphaComponent(CGFloat(stroke?["opacity"]?.numberValue ?? 1)),
            .strokeWidth: strokeWidthPercent
        ]
        let string = NSAttributedString(string: renderedContent, attributes: attributes)
        let baseline = text?.extra["baseline"]?.stringValue ?? "middle"
        let line = CTLineCreateWithAttributedString(string)
        let glyphBounds = CTLineGetImageBounds(line, context)
        let x: CGFloat
        switch text?.align {
        case "left", "start":
            x = -glyphBounds.minX
        case "right", "end":
            x = CGFloat(width) - glyphBounds.maxX
        default:
            x = (CGFloat(width) - glyphBounds.width) / 2 - glyphBounds.minX
        }
        let y: CGFloat
        switch baseline {
        case "top", "hanging":
            y = CGFloat(height) - glyphBounds.maxY
        case "bottom", "ideographic":
            y = -glyphBounds.minY
        default:
            y = (CGFloat(height) - glyphBounds.height) / 2 - glyphBounds.minY
        }
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
        NSGraphicsContext.restoreGraphicsState()
        guard let cgImage = context.makeImage() else { return nil }
        let texture = try? textureLoader.newTexture(cgImage: cgImage, options: [
            MTKTextureLoader.Option.SRGB: false
        ])
        if let texture { textTextures[key] = texture }
        return texture
    }

    private func textAlignment(_ raw: String?) -> NSTextAlignment {
        switch raw {
        case "left", "start": return .left
        case "right", "end": return .right
        default: return .center
        }
    }

    private func transformedText(_ text: String, transform: String) -> String {
        switch transform {
        case "uppercase": return text.uppercased()
        case "lowercase": return text.lowercased()
        case "capitalize": return text.capitalized
        default: return text
        }
    }

    private func resolvedFont(family: String?, size: CGFloat, weight rawWeight: String?) -> NSFont {
        if let family, let font = NSFont(name: family, size: size) {
            return font
        }
        return NSFont.systemFont(ofSize: size, weight: fontWeight(rawWeight))
    }

    private func fontWeight(_ rawWeight: String?) -> NSFont.Weight {
        let numeric = Double(rawWeight ?? "") ?? 400
        switch numeric {
        case 850...: return .black
        case 750..<850: return .heavy
        case 650..<750: return .bold
        case 550..<650: return .semibold
        case 450..<550: return .medium
        default: return .regular
        }
    }

    private func syncVideoProviders(frameIndex: Int, play: Bool) {
        guard let ir else { return }
        let graph = evaluatedFrame(ir: ir, frameIndex: frameIndex).graph
        for node in graph.visualNodes where node.kind == "video" {
            _ = videoTexture(for: node, frameIndex: frameIndex, fps: graph.fps)
            videoProviders[node.clipId]?.sync(mediaTime: node.mediaTime, playing: play)
        }
        if !play {
            pauseVideoProviders()
        }
    }

    private func pauseVideoProviders() {
        for provider in videoProviders.values {
            provider.pause()
        }
    }

    private var isRealtimeInteraction: Bool {
        isPlaying || isLiveScrubbing
    }

    private func motionBlurSampleBudget() -> Int {
        if isLiveScrubbing {
            return 6
        }
        if isPlaying {
            return 12
        }
        return PlatformFXCapabilities.macOSNativeRuntime.maxPreviewSamples
    }

    private func quadVertices(for node: RenderGraphNode, graph: RenderGraphSnapshot) -> [NativeRenderVertex] {
        let transform = node.transform
        let compWidth = Float(max(1, graph.width))
        let compHeight = Float(max(1, graph.height))
        let centerX = Float(transform.x + transform.width * transform.anchorX)
        let centerY = Float(transform.y + transform.height * transform.anchorY)
        let left = Float(-transform.width * transform.anchorX)
        let right = Float(transform.width * (1 - transform.anchorX))
        let top = Float(-transform.height * transform.anchorY)
        let bottom = Float(transform.height * (1 - transform.anchorY))
        let radians = Float(transform.rotationDegrees * .pi / 180)
        let cosValue = cos(radians)
        let sinValue = sin(radians)
        func ndc(_ local: SIMD2<Float>) -> SIMD2<Float> {
            let skewed = SIMD2<Float>(
                local.x + tan(Float(transform.skewXDegrees * .pi / 180)) * local.y,
                tan(Float(transform.skewYDegrees * .pi / 180)) * local.x + local.y
            )
            let scaled = SIMD2<Float>(skewed.x * Float(transform.scaleX), skewed.y * Float(transform.scaleY))
            let rotated = SIMD2<Float>(
                scaled.x * cosValue - scaled.y * sinValue,
                scaled.x * sinValue + scaled.y * cosValue
            )
            let pixel = SIMD2<Float>(centerX + rotated.x, centerY + rotated.y)
            return SIMD2<Float>(
                pixel.x / compWidth * 2 - 1,
                1 - pixel.y / compHeight * 2
            )
        }
        return [
            NativeRenderVertex(position: ndc(SIMD2<Float>(left, bottom)), uv: SIMD2<Float>(0, 1)),
            NativeRenderVertex(position: ndc(SIMD2<Float>(right, bottom)), uv: SIMD2<Float>(1, 1)),
            NativeRenderVertex(position: ndc(SIMD2<Float>(left, top)), uv: SIMD2<Float>(0, 0)),
            NativeRenderVertex(position: ndc(SIMD2<Float>(right, bottom)), uv: SIMD2<Float>(1, 1)),
            NativeRenderVertex(position: ndc(SIMD2<Float>(right, top)), uv: SIMD2<Float>(1, 0)),
            NativeRenderVertex(position: ndc(SIMD2<Float>(left, top)), uv: SIMD2<Float>(0, 0))
        ]
    }

    private static func makeBackgroundPipeline(device: MTLDevice, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        makePipeline(device: device, pixelFormat: pixelFormat, source: nativeMetalShaderSource, vertex: "native_background_vertex", fragment: "native_background_fragment")
    }

    private static func makeTexturePipeline(device: MTLDevice, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        makePipeline(device: device, pixelFormat: pixelFormat, source: nativeMetalShaderSource, vertex: "native_vertex", fragment: "native_texture_fragment")
    }

    private static func makeAdditiveTexturePipeline(device: MTLDevice, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        makePipeline(device: device, pixelFormat: pixelFormat, source: nativeMetalShaderSource, vertex: "native_vertex", fragment: "native_texture_fragment", additive: true)
    }

    private static func makeShapePipeline(device: MTLDevice, pixelFormat: MTLPixelFormat) -> MTLRenderPipelineState? {
        makePipeline(device: device, pixelFormat: pixelFormat, source: nativeMetalShaderSource, vertex: "native_vertex", fragment: "native_shape_fragment")
    }

    private static func makePipeline(device: MTLDevice, pixelFormat: MTLPixelFormat, source: String, vertex: String, fragment: String, additive: Bool = false) -> MTLRenderPipelineState? {
        do {
            let library = try device.makeLibrary(source: source, options: nil)
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: vertex)
            descriptor.fragmentFunction = library.makeFunction(name: fragment)
            descriptor.colorAttachments[0].pixelFormat = pixelFormat
            descriptor.colorAttachments[0].isBlendingEnabled = true
            descriptor.colorAttachments[0].rgbBlendOperation = .add
            descriptor.colorAttachments[0].alphaBlendOperation = .add
            if additive {
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .one
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = .one
            } else {
                descriptor.colorAttachments[0].sourceRGBBlendFactor = .one
                descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
                descriptor.colorAttachments[0].sourceAlphaBlendFactor = .one
                descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            }
            return try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            NSLog("NativeRenderEngine pipeline creation failed: \(error.localizedDescription)")
            return nil
        }
    }
}

private final class RealtimeVideoSourceProvider {
    private let url: URL
    private let player: AVPlayer
    private let output: AVPlayerItemVideoOutput
    private var lastTexture: CVMetalTexture?
    private var warmedPixelBuffer: CVPixelBuffer?
    private var warmedSample: CMSampleBuffer?
    private var warmedMediaTime = -1.0
    private var lastMediaTime = -1.0
    private var isPlaying = false

    init(url: URL) {
        self.url = url
        let item = AVPlayerItem(url: url)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        item.add(output)
        self.output = output
        self.player = AVPlayer(playerItem: item)
        self.player.isMuted = false
        self.player.actionAtItemEnd = .pause
    }

    func sync(mediaTime: Double, playing: Bool) {
        let target = max(0, mediaTime)
        if playing {
            if !isPlaying {
                warmFrameIfNeeded(at: target)
                player.seek(to: CMTime(seconds: target, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero)
                lastMediaTime = target
                isPlaying = true
                player.play()
            }
            return
        }
        if abs(target - lastMediaTime) > 0.001 || playing != isPlaying {
            warmFrameIfNeeded(at: target)
            player.seek(to: CMTime(seconds: target, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero)
            lastMediaTime = target
        }
        isPlaying = false
        player.pause()
    }

    func scrub(mediaTime: Double) {
        let target = max(0, mediaTime)
        guard abs(target - lastMediaTime) > 0.001 || isPlaying else { return }
        isPlaying = false
        lastMediaTime = target
        player.pause()
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 60_000),
            toleranceBefore: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 60_000),
            toleranceAfter: CMTime(seconds: 1.0 / 30.0, preferredTimescale: 60_000)
        )
    }

    func pause() {
        isPlaying = false
        player.pause()
    }

    func texture(textureCache: CVMetalTextureCache) -> MTLTexture? {
        let itemTime = isPlaying
            ? output.itemTime(forHostTime: CACurrentMediaTime())
            : CMTime(seconds: max(0, lastMediaTime), preferredTimescale: 60_000)

        let playerPixelBuffer = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        let pixelBuffer = playerPixelBuffer ?? warmedPixelBuffer
        if playerPixelBuffer != nil {
            warmedPixelBuffer = nil
            warmedSample = nil
            warmedMediaTime = -1
        }

        guard let pixelBuffer else {
            return lastTexture.flatMap(CVMetalTextureGetTexture)
        }
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            CVPixelBufferGetWidth(pixelBuffer),
            CVPixelBufferGetHeight(pixelBuffer),
            0,
            &cvTexture
        )
        if let cvTexture {
            lastTexture = cvTexture
            return CVMetalTextureGetTexture(cvTexture)
        }
        return lastTexture.flatMap(CVMetalTextureGetTexture)
    }

    private func warmFrameIfNeeded(at mediaTime: Double) {
        let target = max(0, mediaTime)
        guard warmedPixelBuffer == nil || abs(target - warmedMediaTime) > 0.001 else { return }
        warmedPixelBuffer = nil
        warmedSample = nil
        warmedMediaTime = target
        warmedPixelBuffer = makeDeterministicPixelBuffer(at: target)
    }

    private func makeDeterministicPixelBuffer(at mediaTime: Double) -> CVPixelBuffer? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }

        do {
            let reader = try AVAssetReader(asset: asset)
            let start = CMTime(seconds: max(0, mediaTime), preferredTimescale: 60_000)
            let duration = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 60_000)
            reader.timeRange = CMTimeRange(start: start, duration: duration)

            let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true
            ])
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { return nil }
            reader.add(output)
            guard reader.startReading(), let sample = output.copyNextSampleBuffer() else { return nil }
            warmedSample = sample
            return CMSampleBufferGetImageBuffer(sample)
        } catch {
            return nil
        }
    }
}

private struct NativeCachedFrame {
    let revision: String
    let frameIndex: Int
    let graph: RenderGraphSnapshot
    let fxGraph: FXPassGraphSnapshot
}

private struct NativeResolvedNode {
    let node: RenderGraphNode
    let compositeStyleNode: RenderGraphNode?
    let texture: MTLTexture?
    let boundsScaleX: Double
    let boundsScaleY: Double
}

private enum NativeShapeMode: Int {
    case fill = 0
    case border = 1
}

private struct NativeRenderVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
}

private struct NativeBackgroundUniforms {
    var color: SIMD4<Float>
}

private struct NativeLayerUniforms {
    var color: SIMD4<Float>
    var size: SIMD2<Float>
    var radius: Float
    var opacity: Float
    var mode: Float
}

private func rgbaFloat4(_ hex: String) -> SIMD4<Float> {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") { value.removeFirst() }
    if value.count == 3 {
        value = value.map { "\($0)\($0)" }.joined()
    }
    var intValue: UInt64 = 0
    Scanner(string: value).scanHexInt64(&intValue)
    let red = Float((intValue >> 16) & 0xFF) / 255
    let green = Float((intValue >> 8) & 0xFF) / 255
    let blue = Float(intValue & 0xFF) / 255
    return SIMD4<Float>(red, green, blue, 1)
}

private extension NSColor {
    convenience init(hexString: String) {
        let rgba = rgbaFloat4(hexString)
        self.init(
            calibratedRed: CGFloat(rgba.x),
            green: CGFloat(rgba.y),
            blue: CGFloat(rgba.z),
            alpha: CGFloat(rgba.w)
        )
    }
}

private let nativeMetalShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct NativeRenderVertex {
    float2 position;
    float2 uv;
};

struct NativeBackgroundUniforms {
    float4 color;
};

struct NativeLayerUniforms {
    float4 color;
    float2 size;
    float radius;
    float opacity;
    float mode;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut native_background_vertex(uint vid [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.uv = (positions[vid] + 1.0) * 0.5;
    return out;
}

fragment float4 native_background_fragment(VertexOut in [[stage_in]], constant NativeBackgroundUniforms &u [[buffer(0)]]) {
    return u.color;
}

vertex VertexOut native_vertex(const device NativeRenderVertex *vertices [[buffer(0)]], uint vid [[vertex_id]]) {
    VertexOut out;
    out.position = float4(vertices[vid].position, 0.0, 1.0);
    out.uv = vertices[vid].uv;
    return out;
}

float rounded_rect_alpha(float2 uv, float2 size, float radius) {
    if (radius <= 0.0) { return 1.0; }
    float2 p = (uv - 0.5) * size;
    float2 b = size * 0.5 - float2(radius);
    float2 q = abs(p) - b;
    float dist = length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    return 1.0 - smoothstep(-1.0, 1.0, dist);
}

fragment float4 native_texture_fragment(VertexOut in [[stage_in]], texture2d<float> texture [[texture(0)]], constant NativeLayerUniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 color = texture.sample(s, in.uv);
    float coverage = rounded_rect_alpha(in.uv, u.size, u.radius) * u.opacity;
    color.rgb *= coverage;
    color.a *= coverage;
    return color;
}

fragment float4 native_shape_fragment(VertexOut in [[stage_in]], constant NativeLayerUniforms &u [[buffer(0)]]) {
    float outer = rounded_rect_alpha(in.uv, u.size, u.radius);
    float borderWidth = floor(u.mode / 10.0);
    float mode = fmod(u.mode, 10.0);
    float alpha = outer;
    if (mode >= 1.0) {
        float2 innerSize = max(float2(1.0), u.size - float2(borderWidth * 2.0));
        float innerRadius = max(0.0, u.radius - borderWidth);
        alpha = max(0.0, outer - rounded_rect_alpha(in.uv, innerSize, innerRadius));
    }
    float4 color = u.color;
    color.a *= alpha * u.opacity;
    color.rgb *= color.a;
    return color;
}
"""
