import Foundation

struct RenderGraphSnapshot: Hashable {
    let revision: String
    let frameIndex: Int
    let time: Double
    let fps: Double
    let width: Int
    let height: Int
    let nodes: [RenderGraphNode]
    let diagnostics: [UnitedGateDiagnostic]

    var visualNodes: [RenderGraphNode] {
        nodes.filter { $0.kind != "audio" && $0.kind != "background" }
    }

    var backgroundColor: String {
        nodes
            .filter { $0.kind == "background" }
            .last?
            .fill?
            .color ?? "#FFFFFF"
    }
}

struct RenderGraphNode: Hashable, Identifiable {
    let id: String
    let clipId: String
    let trackId: String
    let kind: String
    let zIndex: Int
    let clip: WorkspaceClip
    let asset: WorkspaceAsset?
    let localTime: Double
    let mediaTime: Double
    let transform: RenderTransform
    let opacity: Double
    let fill: RenderFill?
    let cornerRadius: RenderCornerRadius
    let border: RenderBorder?
    let shadow: RenderShadow?
    let mask: RenderMask?
    let effects: [RenderEffect]
    let rawEffects: JSONValue?
    let rawStyle: [String: JSONValue]
}

struct RenderTransform: Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let anchorX: Double
    let anchorY: Double
    let scaleX: Double
    let scaleY: Double
    let rotationDegrees: Double
    let skewXDegrees: Double
    let skewYDegrees: Double
}

struct RenderFill: Hashable {
    let enabled: Bool
    let color: String
    let opacity: Double
}

struct RenderCornerRadius: Hashable {
    let topLeft: Double
    let topRight: Double
    let bottomRight: Double
    let bottomLeft: Double

    var maxRadius: Double {
        max(0, max(max(topLeft, topRight), max(bottomRight, bottomLeft)))
    }
}

struct RenderBorder: Hashable {
    let enabled: Bool
    let width: Double
    let color: String
    let opacity: Double
    let position: String
}

struct RenderShadow: Hashable {
    let enabled: Bool
    let offsetX: Double
    let offsetY: Double
    let blur: Double
    let spread: Double
    let color: String
    let opacity: Double
}

struct RenderMask: Hashable {
    let enabled: Bool
    let type: String
    let radius: Double
}

struct RenderEffect: Hashable {
    let id: String
    let source: String
    let kind: String
    let enabled: Bool
    let params: JSONValue
    let quality: String
    let scope: String
    let passCategory: FXPassCategory
    let diagnostics: [UnitedGateDiagnostic]
}

struct RenderGraphCompiler {
    func compile(descriptor: HyperFrameFrameDescriptorBridge) -> RenderGraphSnapshot {
        let nodes = descriptor.layers.map { layer in
            RenderGraphNode(
                id: layer.id,
                clipId: layer.clipId,
                trackId: layer.trackId,
                kind: layer.kind,
                zIndex: layer.zIndex,
                clip: layer.clip,
                asset: layer.sourceAsset,
                localTime: layer.localTime,
                mediaTime: layer.mediaTime,
                transform: RenderTransform(
                    x: layer.transform.x,
                    y: layer.transform.y,
                    width: layer.transform.width,
                    height: layer.transform.height,
                    anchorX: layer.transform.anchorX,
                    anchorY: layer.transform.anchorY,
                    scaleX: layer.transform.scaleX,
                    scaleY: layer.transform.scaleY,
                    rotationDegrees: layer.transform.rotationDegrees,
                    skewXDegrees: layer.transform.skewXDegrees,
                    skewYDegrees: layer.transform.skewYDegrees
                ),
                opacity: layer.opacity,
                fill: layer.clip.style.fill.map {
                    RenderFill(enabled: $0.enabled, color: $0.color, opacity: $0.opacity)
                },
                cornerRadius: layer.cornerRadius.renderCornerRadius,
                border: Self.border(from: layer.clip.style.extra["border"], animation: layer.clip.style.keyframes, localTime: layer.localTime),
                shadow: Self.shadow(from: layer.clip.style.extra["shadow"], animation: layer.clip.style.keyframes, localTime: layer.localTime),
                mask: Self.mask(from: layer.clip.style.extra["mask"], fallbackRadius: layer.cornerRadius.renderCornerRadius.maxRadius),
                effects: layer.normalizedEffects.map {
                    RenderEffect(
                        id: $0.id,
                        source: $0.source,
                        kind: $0.kind,
                        enabled: $0.enabled,
                        params: $0.params,
                        quality: $0.quality,
                        scope: $0.scope,
                        passCategory: $0.passCategory,
                        diagnostics: $0.diagnostics
                    )
                },
                rawEffects: layer.effects,
                rawStyle: layer.clip.style.extra
            )
        }

        return RenderGraphSnapshot(
            revision: descriptor.revision,
            frameIndex: descriptor.frameIndex,
            time: descriptor.time,
            fps: descriptor.fps,
            width: descriptor.composition.width,
            height: descriptor.composition.height,
            nodes: nodes,
            diagnostics: descriptor.diagnostics
        )
    }

    private static func border(from value: JSONValue?, animation: [String: [StylePropertyKeyframe]]?, localTime: Double) -> RenderBorder? {
        guard let object = value?.objectValue else { return nil }
        let enabled = object["enabled"]?.boolValue ?? true
        let opacity = animatedValue(animation?["border.opacity"], localTime: localTime, fallback: object["opacity"]?.numberValue ?? 1)
        return RenderBorder(
            enabled: enabled,
            width: object["width"]?.numberValue ?? 0,
            color: object["color"]?.stringValue ?? "#FFFFFF",
            opacity: opacity,
            position: object["position"]?.stringValue ?? object["align"]?.stringValue ?? "inside"
        )
    }

    private static func shadow(from value: JSONValue?, animation: [String: [StylePropertyKeyframe]]?, localTime: Double) -> RenderShadow? {
        guard let object = value?.objectValue else { return nil }
        let enabled = object["enabled"]?.boolValue ?? true
        let opacity = animatedValue(animation?["shadow.opacity"], localTime: localTime, fallback: object["opacity"]?.numberValue ?? 1)
        return RenderShadow(
            enabled: enabled,
            offsetX: object["offsetX"]?.numberValue ?? object["x"]?.numberValue ?? 0,
            offsetY: object["offsetY"]?.numberValue ?? object["y"]?.numberValue ?? 0,
            blur: object["blur"]?.numberValue ?? object["radius"]?.numberValue ?? 0,
            spread: object["spread"]?.numberValue ?? 0,
            color: object["color"]?.stringValue ?? "#000000",
            opacity: opacity
        )
    }

    private static func mask(from value: JSONValue?, fallbackRadius: Double) -> RenderMask? {
        guard let object = value?.objectValue else {
            return fallbackRadius > 0 ? RenderMask(enabled: true, type: "roundedRect", radius: fallbackRadius) : nil
        }
        return RenderMask(
            enabled: object["enabled"]?.boolValue ?? true,
            type: object["type"]?.stringValue ?? "roundedRect",
            radius: object["radius"]?.numberValue ?? fallbackRadius
        )
    }

    private static func animatedValue(_ frames: [StylePropertyKeyframe]?, localTime: Double, fallback: Double) -> Double {
        guard let frames = frames?.sorted(by: { $0.time < $1.time }), !frames.isEmpty else { return fallback }
        if localTime <= frames[0].time { return frames[0].value }
        guard let last = frames.last else { return fallback }
        if localTime >= last.time { return last.value }
        for index in 1..<frames.count {
            let previous = frames[index - 1]
            let next = frames[index]
            guard localTime <= next.time else { continue }
            let span = max(0.0001, next.time - previous.time)
            let progress = min(1, max(0, (localTime - previous.time) / span))
            return previous.value + (next.value - previous.value) * progress
        }
        return fallback
    }
}

private extension HyperFrameCornerRadiusBridge {
    var renderCornerRadius: RenderCornerRadius {
        RenderCornerRadius(topLeft: topLeft, topRight: topRight, bottomRight: bottomRight, bottomLeft: bottomLeft)
    }
}

extension JSONValue {
    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value }
        if case .string(let value) = self { return Double(value) }
        return nil
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}
