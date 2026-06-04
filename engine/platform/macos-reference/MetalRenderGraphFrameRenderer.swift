import AppKit
import AVFoundation
import CoreMedia
import CoreText
import CoreVideo
import Metal
import MetalKit

final class MetalRenderGraphFrameRenderer: NativeFrameRenderer {
    let backendName = "metal-rendergraph-cvpixelbuffer"
    let target: NativeFrameRenderTarget

    private let workspaceURL: URL
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let textureLoader: MTKTextureLoader
    private let fxRuntime: MetalFXRuntime
    private var textureCache: CVMetalTextureCache?
    private let texturePipeline: MTLRenderPipelineState
    private let additiveTexturePipeline: MTLRenderPipelineState
    private let additiveFloatTexturePipeline: MTLRenderPipelineState
    private let shapePipeline: MTLRenderPipelineState

    private var imageTextures: [String: MTLTexture] = [:]
    private var textTextures: [String: MTLTexture] = [:]
    private var shadowTextures: [String: MTLTexture] = [:]
    private var videoProviders: [String: DeterministicVideoSourceProvider] = [:]

    init?(workspaceURL: URL, target: NativeFrameRenderTarget, device: any MTLDevice) {
        guard
            let commandQueue = device.makeCommandQueue()
        else { return nil }
        self.workspaceURL = workspaceURL
        self.target = target
        self.device = device
        self.commandQueue = commandQueue
        self.textureLoader = MTKTextureLoader(device: device)
        CVMetalTextureCacheCreate(nil, nil, device, nil, &textureCache)
        guard
            let texturePipeline = Self.makePipeline(device: device, pixelFormat: .bgra8Unorm, vertex: "metal_export_vertex", fragment: "metal_export_texture_fragment"),
            let additiveTexturePipeline = Self.makePipeline(device: device, pixelFormat: .bgra8Unorm, vertex: "metal_export_vertex", fragment: "metal_export_texture_fragment", additive: true),
            let additiveFloatTexturePipeline = Self.makePipeline(device: device, pixelFormat: .rgba16Float, vertex: "metal_export_vertex", fragment: "metal_export_texture_fragment", additive: true),
            let shapePipeline = Self.makePipeline(device: device, pixelFormat: .bgra8Unorm, vertex: "metal_export_vertex", fragment: "metal_export_shape_fragment"),
            let fxRuntime = MetalFXRuntime(device: device)
        else { return nil }
        self.texturePipeline = texturePipeline
        self.additiveTexturePipeline = additiveTexturePipeline
        self.additiveFloatTexturePipeline = additiveFloatTexturePipeline
        self.shapePipeline = shapePipeline
        self.fxRuntime = fxRuntime
    }

    func render(
        graph: RenderGraphSnapshot,
        fxPassGraph: FXPassGraphSnapshot,
        context: NativeFrameRenderContext,
        into pixelBuffer: CVPixelBuffer
    ) throws {
        guard let renderTarget = renderTargetTexture(from: pixelBuffer) else {
            throw NativeExportError.contextCreationFailed
        }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = renderTarget
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        let background = metalRGBAFloat4(graph.backgroundColor)
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(background.x),
            green: Double(background.y),
            blue: Double(background.z),
            alpha: Double(background.w)
        )
        guard
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { throw NativeExportError.contextCreationFailed }

        let resolvedNodes = try resolveNodes(graph: graph, fxGraph: fxPassGraph, context: context, commandBuffer: commandBuffer)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            throw NativeExportError.contextCreationFailed
        }
        for resolvedNode in resolvedNodes {
            try drawNode(resolvedNode, graph: graph, fxGraph: fxPassGraph, encoder: encoder)
        }

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        if let error = commandBuffer.error {
            throw error
        }
    }

    private func renderTargetTexture(from pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let textureCache else { return nil }
        var cvTexture: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(
            nil,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            target.width,
            target.height,
            0,
            &cvTexture
        )
        guard let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }

    private func resolveNodes(
        graph: RenderGraphSnapshot,
        fxGraph: FXPassGraphSnapshot,
        context: NativeFrameRenderContext,
        commandBuffer: MTLCommandBuffer
    ) throws -> [MetalExportResolvedNode] {
        try graph.visualNodes
            .sorted { $0.zIndex < $1.zIndex }
            .map { node in
                if let motionBlurPass = motionBlurPass(for: node, fxGraph: fxGraph),
                   let blurredTexture = try renderMotionBlurTexture(
                       node: node,
                       graph: graph,
                       fxGraph: fxGraph,
                       pass: motionBlurPass,
                       context: context,
                       commandBuffer: commandBuffer
                   ) {
                    let fullscreenNode = fullscreenTextureNode(from: node, graph: graph)
                    let postTemporal = fxRuntime.resolve(
                        sourceTexture: blurredTexture,
                        node: fullscreenNode,
                        fxGraph: fxGraph,
                        commandBuffer: commandBuffer,
                        includePreTransform: false
                    )
                    return MetalExportResolvedNode(
                        node: fullscreenNode,
                        compositeStyleNode: node,
                        texture: postTemporal.texture,
                        boundsScaleX: 1,
                        boundsScaleY: 1
                    )
                }
                guard let sourceTexture = try sourceTexture(for: node) else {
                    return MetalExportResolvedNode(node: node, compositeStyleNode: node, texture: nil, boundsScaleX: 1, boundsScaleY: 1)
                }
                let resolved = fxRuntime.resolve(
                    sourceTexture: sourceTexture,
                    node: node,
                    fxGraph: fxGraph,
                    commandBuffer: commandBuffer
                )
                return MetalExportResolvedNode(
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
        fxGraph: FXPassGraphSnapshot,
        pass: FXPassNode,
        context: NativeFrameRenderContext,
        commandBuffer: MTLCommandBuffer
    ) throws -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: max(1, graph.width),
            height: max(1, graph.height),
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .renderTarget]
        descriptor.storageMode = .private
        guard let accumulationTexture = device.makeTexture(descriptor: descriptor) else { return nil }

        let samplePlan = MotionBlurQualityPlanner.plan(
            pass: pass,
            node: node,
            frameTime: context.time,
            fps: context.fps,
            maxSamples: fxGraph.capabilities.maxExportSamples,
            nodeAtTime: { sampleTime in
                context.sample(sampleTime)?.graph.visualNodes.first(where: { $0.clipId == node.clipId })
            }
        )
        var resolvedSamples: [(node: RenderGraphNode, texture: MTLTexture, boundsScaleX: Double, boundsScaleY: Double, weight: Double)] = []
        for sample in samplePlan.samples.sorted(by: { $0.time < $1.time }) {
            guard
                let renderSample = context.sample(sample.time),
                let sampleNode = renderSample.graph.visualNodes.first(where: { $0.clipId == node.clipId }),
                let sampleSourceTexture = try sourceTexture(for: sampleNode)
            else { continue }
            let sampleResolved = fxRuntime.resolve(
                sourceTexture: sampleSourceTexture,
                node: sampleNode,
                fxGraph: renderSample.fxPassGraph,
                commandBuffer: commandBuffer,
                includePostTransform: false
            )
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

    private func drawNode(
        _ resolvedNode: MetalExportResolvedNode,
        graph: RenderGraphSnapshot,
        fxGraph: FXPassGraphSnapshot,
        encoder: MTLRenderCommandEncoder
    ) throws {
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
        _ = fxGraph
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
        let pipeline = pipeline ?? texturePipeline
        let drawNode = scaledNode(node, boundsScaleX: boundsScaleX, boundsScaleY: boundsScaleY)
        var vertices = quadVertices(for: drawNode, graph: graph)
        var uniforms = MetalExportLayerUniforms(
            color: SIMD4<Float>(1, 1, 1, Float(node.opacity * opacityScale)),
            size: SIMD2<Float>(Float(drawNode.transform.width), Float(drawNode.transform.height)),
            radius: Float(node.mask?.radius ?? node.cornerRadius.maxRadius),
            opacity: Float(node.opacity * opacityScale),
            mode: 0,
            shapeKind: Float(shapeKindValue(for: node)),
            sourceRect: sourceRect(for: node, texture: texture),
            cornerRadii: cornerRadii(for: node)
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<MetalExportVertex>.stride * vertices.count, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MetalExportLayerUniforms>.stride, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    private func drawShape(
        _ node: RenderGraphNode,
        graph: RenderGraphSnapshot,
        encoder: MTLRenderCommandEncoder,
        mode: MetalExportShapeMode
    ) {
        var vertices = quadVertices(for: node, graph: graph)
        var uniforms = MetalExportLayerUniforms(
            color: fillColor(for: node),
            size: SIMD2<Float>(Float(node.transform.width), Float(node.transform.height)),
            radius: Float(node.mask?.radius ?? node.cornerRadius.maxRadius),
            opacity: Float(node.opacity),
            mode: Float(mode.rawValue),
            shapeKind: Float(shapeKindValue(for: node)),
            sourceRect: SIMD4<Float>(0, 0, 1, 1),
            cornerRadii: cornerRadii(for: node)
        )
        encoder.setRenderPipelineState(shapePipeline)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<MetalExportVertex>.stride * vertices.count, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MetalExportLayerUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    private func drawBorder(
        _ node: RenderGraphNode,
        border: RenderBorder,
        graph: RenderGraphSnapshot,
        encoder: MTLRenderCommandEncoder
    ) {
        var vertices = quadVertices(for: node, graph: graph)
        var color = metalRGBAFloat4(border.color)
        color.w *= Float(border.opacity)
        var uniforms = MetalExportLayerUniforms(
            color: color,
            size: SIMD2<Float>(Float(node.transform.width), Float(node.transform.height)),
            radius: Float(node.mask?.radius ?? node.cornerRadius.maxRadius),
            opacity: Float(node.opacity),
            mode: Float(MetalExportShapeMode.border.rawValue + Int(max(1, border.width)) * 10),
            shapeKind: Float(shapeKindValue(for: node)),
            sourceRect: SIMD4<Float>(0, 0, 1, 1),
            cornerRadii: cornerRadii(for: node)
        )
        encoder.setRenderPipelineState(shapePipeline)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<MetalExportVertex>.stride * vertices.count, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MetalExportLayerUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    private func drawShadow(
        _ node: RenderGraphNode,
        shadow: RenderShadow,
        graph: RenderGraphSnapshot,
        encoder: MTLRenderCommandEncoder
    ) {
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
            let shadowNode = shadowTextureNode(
                from: node,
                transform: shadowTransform,
                opacity: shadow.opacity * node.opacity
            )
            drawTexture(
                texture,
                node: shadowNode,
                graph: graph,
                boundsScaleX: 1,
                boundsScaleY: 1,
                encoder: encoder
            )
            return
        }

        let shadowTransform = RenderTransform(
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
        let shadowNode = RenderGraphNode(
            id: node.id,
            clipId: node.clipId,
            trackId: node.trackId,
            kind: node.kind,
            zIndex: node.zIndex,
            clip: node.clip,
            asset: node.asset,
            localTime: node.localTime,
            mediaTime: node.mediaTime,
            transform: shadowTransform,
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
        var color = metalRGBAFloat4(shadow.color)
        color.w *= Float(shadow.opacity)
        var uniforms = MetalExportLayerUniforms(
            color: color,
            size: SIMD2<Float>(Float(shadowTransform.width), Float(shadowTransform.height)),
            radius: Float(node.mask?.radius ?? node.cornerRadius.maxRadius),
            opacity: Float(node.opacity),
            mode: Float(MetalExportShapeMode.fill.rawValue),
            shapeKind: Float(shapeKindValue(for: node)),
            sourceRect: SIMD4<Float>(0, 0, 1, 1),
            cornerRadii: cornerRadii(for: node)
        )
        encoder.setRenderPipelineState(shapePipeline)
        encoder.setVertexBytes(&vertices, length: MemoryLayout<MetalExportVertex>.stride * vertices.count, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<MetalExportLayerUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    private func shadowTexture(for node: RenderGraphNode, shadow: RenderShadow) -> MTLTexture? {
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
            color: NSColor(metalHexString: shadow.color)
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

    private func videoTexture(for node: RenderGraphNode) throws -> MTLTexture? {
        guard let asset = node.asset, let textureCache else { return nil }
        let provider = videoProviders[node.clipId] ?? DeterministicVideoSourceProvider(url: workspaceURL.appendingPathComponent(asset.path))
        videoProviders[node.clipId] = provider
        guard let pixelBuffer = try provider.pixelBuffer(at: node.mediaTime) else { return nil }
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
        guard let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }

    private func imageTexture(for node: RenderGraphNode) -> MTLTexture? {
        guard let asset = node.asset else { return nil }
        if let cached = imageTextures[asset.id] { return cached }
        let url = workspaceURL.appendingPathComponent(asset.path)
        guard
            let image = NSImage(contentsOf: url),
            let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { return nil }
        let texture = try? textureLoader.newTexture(cgImage: cgImage, options: [MTKTextureLoader.Option.SRGB: false])
        if let texture { imageTextures[asset.id] = texture }
        return texture
    }

    private func sourceRect(for node: RenderGraphNode, texture: MTLTexture) -> SIMD4<Float> {
        let mediaWidth = max(1, Double(texture.width))
        let mediaHeight = max(1, Double(texture.height))
        let crop = node.rawStyle["crop"]?.objectValue
        let cropLeft = bounded01(crop?["left"]?.numberValue ?? 0)
        let cropTop = bounded01(crop?["top"]?.numberValue ?? 0)
        let cropRight = bounded01(crop?["right"]?.numberValue ?? 0)
        let cropBottom = bounded01(crop?["bottom"]?.numberValue ?? 0)
        var sx = mediaWidth * cropLeft
        var sy = mediaHeight * cropTop
        var sw = max(1, mediaWidth * (1 - cropLeft - cropRight))
        var sh = max(1, mediaHeight * (1 - cropTop - cropBottom))
        let fit = node.clip.style.fit ?? "cover"
        if fit != "fill" && fit != "contain" {
            let boxRatio = max(1, node.transform.width) / max(1, node.transform.height)
            let mediaRatio = sw / max(1, sh)
            if mediaRatio > boxRatio {
                let nextSw = sh * boxRatio
                sx += (sw - nextSw) / 2
                sw = nextSw
            } else {
                let nextSh = sw / boxRatio
                sy += (sh - nextSh) / 2
                sh = nextSh
            }
        }
        return SIMD4<Float>(
            Float(sx / mediaWidth),
            Float(sy / mediaHeight),
            Float(sw / mediaWidth),
            Float(sh / mediaHeight)
        )
    }

    private func bounded01(_ value: Double) -> Double {
        min(0.95, max(0, value.isFinite ? value : 0))
    }

    private func shapeKindValue(for node: RenderGraphNode) -> Int {
        switch node.clip.shape?.kind {
        case "circle": return 1
        case "line": return 2
        case "arrow": return 3
        default: return 0
        }
    }

    private func textTexture(for node: RenderGraphNode) -> MTLTexture? {
        let content = node.clip.text?.content ?? "Text"
        let text = node.clip.text
        let key = "\(node.clipId)|\(content)|\(text?.fontFamily ?? "")|\(text?.fontWeight ?? "")|\(text?.fontSize ?? 48)|\(text?.color ?? "#111827")|\(Int(node.transform.width))x\(Int(node.transform.height))|\(text?.extra ?? [:])|\(node.rawStyle)"
        if let cached = textTextures[key] { return cached }
        let width = max(1, Int(node.transform.width.rounded()))
        let height = max(1, Int(node.transform.height.rounded()))
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
                color: NSColor(metalHexString: shadow?["color"]?.stringValue ?? "#000000")
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
            .foregroundColor: NSColor(metalHexString: text?.color ?? "#111827"),
            .paragraphStyle: paragraph,
            .kern: CGFloat(text?.extra["letterSpacing"]?.numberValue ?? 0),
            .strokeColor: NSColor(metalHexString: stroke?["color"]?.stringValue ?? text?.color ?? "#111827")
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
        let texture = try? textureLoader.newTexture(cgImage: cgImage, options: [MTKTextureLoader.Option.SRGB: false])
        if let texture { textTextures[key] = texture }
        return texture
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
        case 350..<450: return .regular
        case 250..<350: return .light
        default: return .regular
        }
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

    private func fillColor(for node: RenderGraphNode) -> SIMD4<Float> {
        let fill = node.fill
        var color = metalRGBAFloat4(fill?.color ?? node.clip.style.fill?.color ?? "#FFFFFF")
        color.w *= Float(fill?.opacity ?? node.clip.style.fill?.opacity ?? 1)
        return color
    }

    private func cornerRadii(for node: RenderGraphNode) -> SIMD4<Float> {
        if let mask = node.mask {
            let radius = Float(mask.radius)
            return SIMD4<Float>(radius, radius, radius, radius)
        }
        return SIMD4<Float>(
            Float(node.cornerRadius.topLeft),
            Float(node.cornerRadius.topRight),
            Float(node.cornerRadius.bottomRight),
            Float(node.cornerRadius.bottomLeft)
        )
    }

    private func sourceTexture(for node: RenderGraphNode) throws -> MTLTexture? {
        switch node.kind {
        case "video":
            return try videoTexture(for: node)
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

    private func quadVertices(for node: RenderGraphNode, graph: RenderGraphSnapshot) -> [MetalExportVertex] {
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
            MetalExportVertex(position: ndc(SIMD2<Float>(left, bottom)), uv: SIMD2<Float>(0, 1)),
            MetalExportVertex(position: ndc(SIMD2<Float>(right, bottom)), uv: SIMD2<Float>(1, 1)),
            MetalExportVertex(position: ndc(SIMD2<Float>(left, top)), uv: SIMD2<Float>(0, 0)),
            MetalExportVertex(position: ndc(SIMD2<Float>(right, bottom)), uv: SIMD2<Float>(1, 1)),
            MetalExportVertex(position: ndc(SIMD2<Float>(right, top)), uv: SIMD2<Float>(1, 0)),
            MetalExportVertex(position: ndc(SIMD2<Float>(left, top)), uv: SIMD2<Float>(0, 0))
        ]
    }

    private static func makePipeline(device: MTLDevice, pixelFormat: MTLPixelFormat, vertex: String, fragment: String, additive: Bool = false) -> MTLRenderPipelineState? {
        do {
            let library = try device.makeLibrary(source: metalExportShaderSource, options: nil)
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
            NSLog("Metal export pipeline creation failed: \(error.localizedDescription)")
            return nil
        }
    }
}

private final class DeterministicVideoSourceProvider {
    private let url: URL
    private let asset: AVURLAsset
    private let maxCachedFrames = 24
    private var reader: AVAssetReader?
    private var output: AVAssetReaderOutput?
    private var lastTime = -1.0
    private var lastPixelBuffer: CVPixelBuffer?
    private var cachedPixelBuffers: [Int: CVPixelBuffer] = [:]
    private var cachedPixelBufferKeys: [Int] = []
    private lazy var frameRate: Double = {
        let nominalFrameRate = asset.tracks(withMediaType: .video).first?.nominalFrameRate ?? 30
        return Double(nominalFrameRate > 0 ? nominalFrameRate : 30)
    }()

    init(url: URL) {
        self.url = url
        self.asset = AVURLAsset(url: url)
    }

    func pixelBuffer(at seconds: Double) throws -> CVPixelBuffer? {
        let target = max(0, seconds)
        let requestedKey = cacheKey(for: target)
        if let cachedPixelBuffer = cachedPixelBuffers[requestedKey] {
            return cachedPixelBuffer
        }
        if reader == nil || target + 0.001 < lastTime {
            try startReader()
        }
        while let output {
            guard let sample = output.copyNextSampleBuffer() else {
                if let lastPixelBuffer {
                    remember(lastPixelBuffer, for: requestedKey)
                }
                return lastPixelBuffer
            }
            let pts = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if let buffer = CMSampleBufferGetImageBuffer(sample) {
                lastPixelBuffer = buffer
                lastTime = pts
                remember(buffer, for: cacheKey(for: pts))
            }
            if pts + 0.0001 >= target {
                if let lastPixelBuffer {
                    remember(lastPixelBuffer, for: requestedKey)
                }
                return lastPixelBuffer
            }
        }
        if let lastPixelBuffer {
            remember(lastPixelBuffer, for: requestedKey)
        }
        return lastPixelBuffer
    }

    private func cacheKey(for seconds: Double) -> Int {
        Int((seconds * frameRate).rounded())
    }

    private func remember(_ pixelBuffer: CVPixelBuffer, for key: Int) {
        if cachedPixelBuffers[key] == nil {
            cachedPixelBufferKeys.append(key)
        }
        cachedPixelBuffers[key] = pixelBuffer
        while cachedPixelBufferKeys.count > maxCachedFrames {
            let removedKey = cachedPixelBufferKeys.removeFirst()
            cachedPixelBuffers.removeValue(forKey: removedKey)
        }
    }

    private func startReader() throws {
        reader?.cancelReading()
        guard let track = asset.tracks(withMediaType: .video).first else {
            reader = nil
            output = nil
            return
        }
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else {
            throw NativeExportError.contextCreationFailed
        }
        reader.add(output)
        reader.startReading()
        self.reader = reader
        self.output = output
        self.lastTime = -1
        self.lastPixelBuffer = nil
    }
}

private enum MetalExportShapeMode: Int {
    case fill = 0
    case border = 1
}

private struct MetalExportResolvedNode {
    let node: RenderGraphNode
    let compositeStyleNode: RenderGraphNode?
    let texture: MTLTexture?
    let boundsScaleX: Double
    let boundsScaleY: Double
}

private struct MetalExportVertex {
    var position: SIMD2<Float>
    var uv: SIMD2<Float>
}

private struct MetalExportLayerUniforms {
    var color: SIMD4<Float>
    var size: SIMD2<Float>
    var radius: Float
    var opacity: Float
    var mode: Float
    var shapeKind: Float
    var sourceRect: SIMD4<Float>
    var cornerRadii: SIMD4<Float>
}

private func metalRGBAFloat4(_ hex: String) -> SIMD4<Float> {
    var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.hasPrefix("#") { value.removeFirst() }
    if value.count == 3 {
        value = value.map { "\($0)\($0)" }.joined()
    }
    var intValue: UInt64 = 0
    Scanner(string: value).scanHexInt64(&intValue)
    return SIMD4<Float>(
        Float((intValue >> 16) & 0xFF) / 255,
        Float((intValue >> 8) & 0xFF) / 255,
        Float(intValue & 0xFF) / 255,
        1
    )
}

private extension NSColor {
    convenience init(metalHexString: String) {
        let rgba = metalRGBAFloat4(metalHexString)
        self.init(calibratedRed: CGFloat(rgba.x), green: CGFloat(rgba.y), blue: CGFloat(rgba.z), alpha: CGFloat(rgba.w))
    }
}

private let metalExportShaderSource = """
#include <metal_stdlib>
using namespace metal;

struct MetalExportVertex {
    float2 position;
    float2 uv;
};

struct MetalExportLayerUniforms {
    float4 color;
    float2 size;
    float radius;
    float opacity;
    float mode;
    float shapeKind;
    float4 sourceRect;
    float4 cornerRadii;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut metal_export_vertex(const device MetalExportVertex *vertices [[buffer(0)]], uint vid [[vertex_id]]) {
    VertexOut out;
    out.position = float4(vertices[vid].position, 0.0, 1.0);
    out.uv = vertices[vid].uv;
    return out;
}

float rounded_rect_alpha(float2 uv, float2 size, float radius, float4 cornerRadii) {
    float maxCornerRadius = max(max(cornerRadii.x, cornerRadii.y), max(cornerRadii.z, cornerRadii.w));
    float cornerRadius = radius;
    if (uv.x < 0.5 && uv.y < 0.5) {
        cornerRadius = maxCornerRadius > 0.0 ? cornerRadii.x : radius;
    } else if (uv.x >= 0.5 && uv.y < 0.5) {
        cornerRadius = maxCornerRadius > 0.0 ? cornerRadii.y : radius;
    } else if (uv.x >= 0.5 && uv.y >= 0.5) {
        cornerRadius = maxCornerRadius > 0.0 ? cornerRadii.z : radius;
    } else {
        cornerRadius = maxCornerRadius > 0.0 ? cornerRadii.w : radius;
    }
    if (cornerRadius <= 0.0) { return 1.0; }
    float2 p = (uv - 0.5) * size;
    float2 b = size * 0.5 - float2(cornerRadius);
    float2 q = abs(p) - b;
    float dist = length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - cornerRadius;
    return 1.0 - smoothstep(-1.0, 1.0, dist);
}

float ellipse_alpha(float2 uv) {
    float2 p = (uv - 0.5) * 2.0;
    float dist = length(p) - 1.0;
    return 1.0 - smoothstep(-0.015, 0.015, dist);
}

float line_alpha(float2 uv, float width) {
    float distanceToLine = abs(uv.y - 0.5);
    float halfWidth = max(0.004, width * 0.5);
    return 1.0 - smoothstep(halfWidth, halfWidth + 0.01, distanceToLine);
}

float arrow_alpha(float2 uv, float width) {
    float shaft = line_alpha(uv, width) * (1.0 - smoothstep(0.82, 0.9, uv.x));
    float2 tip = float2(0.96, 0.5);
    float2 upper = float2(0.82, 0.32);
    float2 lower = float2(0.82, 0.68);
    float headTop = abs((uv.y - tip.y) - (upper.y - tip.y) / max(0.001, upper.x - tip.x) * (uv.x - tip.x));
    float headBottom = abs((uv.y - tip.y) - (lower.y - tip.y) / max(0.001, lower.x - tip.x) * (uv.x - tip.x));
    float headMask = step(0.78, uv.x);
    float head = (1.0 - smoothstep(width, width + 0.012, min(headTop, headBottom))) * headMask;
    return max(shaft, head);
}

float shape_alpha(float2 uv, float2 size, float radius, float4 cornerRadii, float shapeKind) {
    if (shapeKind >= 0.5 && shapeKind < 1.5) {
        return ellipse_alpha(uv);
    }
    if (shapeKind >= 1.5 && shapeKind < 2.5) {
        return line_alpha(uv, max(0.004, 2.0 / max(1.0, size.y)));
    }
    if (shapeKind >= 2.5 && shapeKind < 3.5) {
        return arrow_alpha(uv, max(0.004, 2.0 / max(1.0, size.y)));
    }
    return rounded_rect_alpha(uv, size, radius, cornerRadii);
}

fragment float4 metal_export_texture_fragment(VertexOut in [[stage_in]], texture2d<float> texture [[texture(0)]], constant MetalExportLayerUniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 sourceUv = clamp(u.sourceRect.xy + in.uv * u.sourceRect.zw, float2(0.0), float2(1.0));
    float4 color = texture.sample(s, sourceUv);
    float coverage = shape_alpha(in.uv, u.size, u.radius, u.cornerRadii, u.shapeKind) * u.opacity;
    color.rgb *= coverage;
    color.a *= coverage;
    return color;
}

fragment float4 metal_export_shape_fragment(VertexOut in [[stage_in]], constant MetalExportLayerUniforms &u [[buffer(0)]]) {
    float outer = shape_alpha(in.uv, u.size, u.radius, u.cornerRadii, u.shapeKind);
    float borderWidth = floor(u.mode / 10.0);
    float mode = fmod(u.mode, 10.0);
    float alpha = outer;
    if (mode >= 1.0) {
        float2 innerSize = max(float2(1.0), u.size - float2(borderWidth * 2.0));
        float innerRadius = max(0.0, u.radius - borderWidth);
        float4 innerRadii = max(float4(0.0), u.cornerRadii - float4(borderWidth));
        alpha = max(0.0, outer - shape_alpha(in.uv, innerSize, innerRadius, innerRadii, u.shapeKind));
    }
    float4 color = u.color;
    color.a *= alpha * u.opacity;
    color.rgb *= color.a;
    return color;
}
"""
