import Foundation

struct HyperFrameTimingContract: Hashable {
    let version = 1
    let timeBase = "integer-frame-index"
    let fps: Double
    let frameDurationSeconds: Double
    let clipRangePolicy = "half-open-start-inclusive-end-exclusive"
    let seekPolicy = "frame-indexed-deterministic"
}

struct HyperFramePixelGeometryContract: Hashable {
    let version = 1
    let coordinateSpace = "composition-pixels"
    let origin = "top-left"
    let units = "px"
    let rounding = "float-until-raster-boundary"
    let anchorPolicy = "resolved-by-hyperframe-renderer"
    let boundsPolicy = "render-before-encode"
    let alpha = "premultiplied"
    let colorSpace = "srgb"
    let unsupportedGeometry: [String]
}

struct HyperFrameContractBridge: Hashable {
    let version = 1
    let pixelGeometry: HyperFramePixelGeometryContract
    let frameTiming: HyperFrameTimingContract
}

struct HyperFrameIRAssetBridge: Hashable {
    let id: String
    let type: String
    let path: String
    let width: Int?
    let height: Int?
    let duration: Double?
    let fps: Double?
}

struct HyperFrameIRLayerBridge: Hashable, Identifiable {
    let id: String
    let clipId: String
    let trackId: String
    let kind: String
    let zIndex: Int
    let timing: Timing
    let asset: HyperFrameIRAssetBridge?
    let clip: WorkspaceClip
    let sourceAsset: WorkspaceAsset?
    let muted: Bool

    struct Timing: Hashable {
        let start: Double
        let duration: Double
        let end: Double
        let trimIn: Double
    }
}

struct HyperFrameIRBridge: Hashable {
    let version = 1
    let revision: String
    let composition: WorkspaceComposition
    let durationSeconds: Double
    let fps: Double
    let contracts: HyperFrameContractBridge
    let layers: [HyperFrameIRLayerBridge]
    let diagnostics: [UnitedGateDiagnostic]
}

struct HyperFrameEffectInstanceBridge: Hashable {
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

struct HyperFrameLayerTransformBridge: Hashable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let centerX: Double
    let centerY: Double
    let originX: Double
    let originY: Double
    let anchorX: Double
    let anchorY: Double
    let scaleX: Double
    let scaleY: Double
    let rotationDegrees: Double
    let rotationRadians: Double
    let skewXDegrees: Double
    let skewYDegrees: Double
    let skewXRadians: Double
    let skewYRadians: Double
}

struct HyperFrameCornerRadiusBridge: Hashable {
    let topLeft: Double
    let topRight: Double
    let bottomRight: Double
    let bottomLeft: Double
}

struct HyperFrameMotionBridge: Hashable {
    let velocityX: Double
    let velocityY: Double
    let speed: Double
    let angularVelocityDegrees: Double
    let scaleVelocityX: Double
    let scaleVelocityY: Double
    let skewVelocityX: Double
    let skewVelocityY: Double
    let opacityVelocity: Double
}

struct HyperFrameFrameDescriptorLayerBridge: Hashable, Identifiable {
    let id: String
    let clipId: String
    let trackId: String
    let kind: String
    let zIndex: Int
    let localTime: Double
    let mediaTime: Double
    let timing: HyperFrameIRLayerBridge.Timing
    let asset: HyperFrameIRAssetBridge?
    let clip: WorkspaceClip
    let sourceAsset: WorkspaceAsset?
    let transform: HyperFrameLayerTransformBridge
    let opacity: Double
    let cornerRadius: HyperFrameCornerRadiusBridge
    let crop: JSONValue?
    let blendMode: String
    let filters: JSONValue?
    let effects: JSONValue?
    let normalizedEffects: [HyperFrameEffectInstanceBridge]
    let motion: HyperFrameMotionBridge
    let muted: Bool
}

struct HyperFrameFrameDescriptorBridge: Hashable {
    let version = 1
    let revision: String
    let time: Double
    let frameIndex: Int
    let frameTime: Double
    let frameDurationSeconds: Double
    let fps: Double
    let contracts: HyperFrameContractBridge
    let composition: WorkspaceComposition
    let activeLayerIds: [String]
    let layers: [HyperFrameFrameDescriptorLayerBridge]
    let diagnostics: [UnitedGateDiagnostic]
}

struct CanonicalHyperFrameBridge {
    private struct AnimationFrame {
        var time: Double
        var value: Double
        var easing: String?
    }

    private struct AnimationState {
        var x = Double.nan
        var y = Double.nan
        var positionX = Double.nan
        var positionY = Double.nan
        var centerX = Double.nan
        var centerY = Double.nan
        var opacity = 1.0
        var translateX = 0.0
        var translateY = 0.0
        var scaleX = 1.0
        var scaleY = 1.0
        var rotation = 0.0
        var skewX = 0.0
        var skewY = 0.0
        var cornerRadius = Double.nan
        var blur = Double.nan
        var brightness = Double.nan
        var contrast = Double.nan
        var saturation = Double.nan
        var exposure = Double.nan
        var hue = Double.nan
        var grayscale = Double.nan
        var sepia = Double.nan
        var invert = Double.nan
    }

    func link(snapshot: ProjectSnapshot, diagnostics: [UnitedGateDiagnostic]) -> HyperFrameIRBridge {
        let assetsById = Dictionary(uniqueKeysWithValues: snapshot.manifest.assets.map { ($0.id, $0) })
        let orderedClips = orderedTracks(snapshot.timeline.tracks).filter { $0.isHidden != true }.flatMap { track in
            track.clips.sorted { $0.start < $1.start }.map { clip in
                (track: track, clip: clip)
            }
        }
        let layers = orderedClips.enumerated().map { clipIndex, entry in
            let track = entry.track
            let clip = entry.clip
            let asset = clip.assetId.flatMap { assetsById[$0] }
            return HyperFrameIRLayerBridge(
                id: clip.id,
                clipId: clip.id,
                trackId: clip.trackId.isEmpty ? track.id : clip.trackId,
                kind: clip.type,
                zIndex: orderedClips.count - clipIndex - 1,
                timing: .init(start: clip.start, duration: clip.duration, end: clip.start + clip.duration, trimIn: clip.trimIn),
                asset: asset.map {
                    HyperFrameIRAssetBridge(id: $0.id, type: $0.type, path: $0.path, width: $0.width, height: $0.height, duration: $0.duration, fps: $0.fps)
                },
                clip: clip,
                sourceAsset: asset,
                muted: track.isMuted ?? false
            )
        }
        return HyperFrameIRBridge(
            revision: snapshot.fullSignature,
            composition: snapshot.composition,
            durationSeconds: snapshot.composition.durationSeconds,
            fps: snapshot.composition.fps,
            contracts: contracts(for: snapshot.composition),
            layers: layers,
            diagnostics: diagnostics
        )
    }

    func evaluate(ir: HyperFrameIRBridge, frameIndex: Int) -> HyperFrameFrameDescriptorBridge {
        let safeFPS = max(1, ir.fps)
        let clampedFrame = min(max(0, frameIndex), max(0, Int((ir.durationSeconds * safeFPS).rounded()) - 1))
        let time = min(ir.durationSeconds, max(0, Double(clampedFrame) / safeFPS))
        return evaluate(ir: ir, timeSeconds: time, frameIndex: clampedFrame)
    }

    func evaluate(ir: HyperFrameIRBridge, timeSeconds: Double, subframe: Bool = false) -> HyperFrameFrameDescriptorBridge {
        let safeFPS = max(1, ir.fps)
        let requestedTime = min(ir.durationSeconds, max(0, timeSeconds))
        let frameIndex = min(max(0, Int((requestedTime * safeFPS).rounded())), max(0, Int((ir.durationSeconds * safeFPS).rounded())))
        let frameTime = min(ir.durationSeconds, max(0, Double(frameIndex) / safeFPS))
        return evaluate(ir: ir, timeSeconds: subframe ? requestedTime : frameTime, frameIndex: frameIndex)
    }

    private func evaluate(ir: HyperFrameIRBridge, timeSeconds: Double, frameIndex: Int) -> HyperFrameFrameDescriptorBridge {
        let safeFPS = max(1, ir.fps)
        let time = min(ir.durationSeconds, max(0, timeSeconds))
        let layers = ir.layers.compactMap { evaluate(layer: $0, ir: ir, time: time, frameIndex: frameIndex) }
            .sorted { $0.zIndex < $1.zIndex }
        return HyperFrameFrameDescriptorBridge(
            revision: ir.revision,
            time: time,
            frameIndex: frameIndex,
            frameTime: time,
            frameDurationSeconds: 1 / safeFPS,
            fps: safeFPS,
            contracts: ir.contracts,
            composition: ir.composition,
            activeLayerIds: layers.map(\.id),
            layers: layers,
            diagnostics: ir.diagnostics
        )
    }

    func legacyPreviewSnapshot(from descriptor: HyperFrameFrameDescriptorBridge, backgroundColor: SIMD4<Float>) -> FrameDescriptorSnapshot {
        FrameDescriptorSnapshot(
            frameIndex: descriptor.frameIndex,
            fps: descriptor.fps,
            width: descriptor.composition.width,
            height: descriptor.composition.height,
            layers: descriptor.layers.map { layer in
                EvaluatedLayer(
                    clip: layer.clip,
                    asset: layer.sourceAsset,
                    localTime: layer.localTime,
                    mediaTime: layer.mediaTime,
                    x: layer.transform.x,
                    y: layer.transform.y,
                    width: layer.transform.width,
                    height: layer.transform.height,
                    anchorX: layer.transform.anchorX,
                    anchorY: layer.transform.anchorY,
                    opacity: layer.opacity,
                    rotation: layer.transform.rotationDegrees,
                    scaleX: layer.transform.scaleX,
                    scaleY: layer.transform.scaleY,
                    translateX: 0,
                    translateY: 0,
                    skewX: layer.transform.skewXDegrees,
                    skewY: layer.transform.skewYDegrees,
                    effects: layer.effects
                )
            },
            backgroundColor: backgroundColor
        )
    }

    private func contracts(for composition: WorkspaceComposition) -> HyperFrameContractBridge {
        HyperFrameContractBridge(
            pixelGeometry: HyperFramePixelGeometryContract(unsupportedGeometry: []),
            frameTiming: HyperFrameTimingContract(fps: composition.fps, frameDurationSeconds: 1 / max(1, composition.fps))
        )
    }

    private func evaluate(layer: HyperFrameIRLayerBridge, ir: HyperFrameIRBridge, time: Double, frameIndex: Int) -> HyperFrameFrameDescriptorLayerBridge? {
        guard isActive(layer: layer, frameIndex: frameIndex, fps: ir.fps) else { return nil }
        let style = layer.clip.style
        let localTime = max(0, time - layer.timing.start)
        let width = bounded(style.width, fallback: 1, min: 1, max: 100_000)
        let height = bounded(style.height, fallback: 1, min: 1, max: 100_000)
        let anchorX = bounded(style.anchorX ?? 0.5, fallback: 0.5, min: -10, max: 10)
        let anchorY = bounded(style.anchorY ?? 0.5, fallback: 0.5, min: -10, max: 10)
        let animation = evaluateAnimation(for: layer.clip, localTime: localTime)
        let previousAnimation = evaluateAnimation(for: layer.clip, localTime: max(0, localTime - 1 / max(1, ir.fps)))
        let position = resolvedPosition(style: style, animation: animation, width: width, height: height, anchorX: anchorX, anchorY: anchorY)
        let previousPosition = resolvedPosition(style: style, animation: previousAnimation, width: width, height: height, anchorX: anchorX, anchorY: anchorY)
        let centerX = position.x + width * anchorX + animation.translateX
        let centerY = position.y + height * anchorY + animation.translateY
        let previousCenterX = previousPosition.x + width * anchorX + previousAnimation.translateX
        let previousCenterY = previousPosition.y + height * anchorY + previousAnimation.translateY
        let fps = max(1, ir.fps)
        let scaleX = bounded(style.scaleX * animation.scaleX, fallback: 1, min: -100, max: 100)
        let scaleY = bounded(style.scaleY * animation.scaleY, fallback: 1, min: -100, max: 100)
        let previousScaleX = bounded(style.scaleX * previousAnimation.scaleX, fallback: 1, min: -100, max: 100)
        let previousScaleY = bounded(style.scaleY * previousAnimation.scaleY, fallback: 1, min: -100, max: 100)
        let rotation = style.rotation + animation.rotation
        let previousRotation = style.rotation + previousAnimation.rotation
        let skewX = bounded((style.skewX ?? 0) + animation.skewX, fallback: 0, min: -89.9, max: 89.9)
        let skewY = bounded((style.skewY ?? 0) + animation.skewY, fallback: 0, min: -89.9, max: 89.9)
        let previousSkewX = bounded((style.skewX ?? 0) + previousAnimation.skewX, fallback: 0, min: -89.9, max: 89.9)
        let previousSkewY = bounded((style.skewY ?? 0) + previousAnimation.skewY, fallback: 0, min: -89.9, max: 89.9)
        let opacity = clamp01(style.opacity * animation.opacity, fallback: 1)
        let previousOpacity = clamp01(style.opacity * previousAnimation.opacity, fallback: 1)
        return HyperFrameFrameDescriptorLayerBridge(
            id: layer.id,
            clipId: layer.clipId,
            trackId: layer.trackId,
            kind: layer.kind,
            zIndex: layer.zIndex,
            localTime: localTime,
            mediaTime: layer.timing.trimIn + localTime,
            timing: layer.timing,
            asset: layer.asset,
            clip: layer.clip,
            sourceAsset: layer.sourceAsset,
            transform: .init(
                x: centerX - width * anchorX,
                y: centerY - height * anchorY,
                width: width,
                height: height,
                centerX: centerX,
                centerY: centerY,
                originX: width * anchorX,
                originY: height * anchorY,
                anchorX: anchorX,
                anchorY: anchorY,
                scaleX: scaleX,
                scaleY: scaleY,
                rotationDegrees: rotation,
                rotationRadians: rotation * .pi / 180,
                skewXDegrees: skewX,
                skewYDegrees: skewY,
                skewXRadians: skewX * .pi / 180,
                skewYRadians: skewY * .pi / 180
            ),
            opacity: opacity,
            cornerRadius: cornerRadius(style: style, animation: animation),
            crop: style.extra["crop"],
            blendMode: style.extra["blendMode"]?.stringValue ?? "source-over",
            filters: animatedFilters(style: style, animation: animation),
            effects: style.effects,
            normalizedEffects: normalizedEffects(style.effects, layerID: layer.id),
            motion: .init(
                velocityX: (centerX - previousCenterX) * fps,
                velocityY: (centerY - previousCenterY) * fps,
                speed: hypot((centerX - previousCenterX) * fps, (centerY - previousCenterY) * fps),
                angularVelocityDegrees: (rotation - previousRotation) * fps,
                scaleVelocityX: (scaleX - previousScaleX) * fps,
                scaleVelocityY: (scaleY - previousScaleY) * fps,
                skewVelocityX: (skewX - previousSkewX) * fps,
                skewVelocityY: (skewY - previousSkewY) * fps,
                opacityVelocity: (opacity - previousOpacity) * fps
            ),
            muted: layer.muted
        )
    }

    private func isActive(layer: HyperFrameIRLayerBridge, frameIndex: Int, fps: Double) -> Bool {
        let startFrame = max(0, Int((layer.timing.start * fps).rounded()))
        let durationFrames = max(1, Int((layer.timing.duration * fps).rounded()))
        let endFrame = startFrame + durationFrames
        return frameIndex >= startFrame && frameIndex < endFrame
    }

    private func resolvedPosition(style: VisualLayerStyle, animation: AnimationState, width: Double, height: Double, anchorX: Double, anchorY: Double) -> (x: Double, y: Double) {
        var x = animation.x.isFinite ? animation.x : style.x
        var y = animation.y.isFinite ? animation.y : style.y
        if animation.positionX.isFinite { x = animation.positionX - width * anchorX }
        if animation.positionY.isFinite { y = animation.positionY - height * anchorY }
        if animation.centerX.isFinite { x = animation.centerX - width / 2 }
        if animation.centerY.isFinite { y = animation.centerY - height / 2 }
        return (
            bounded(x, fallback: style.x, min: -1_000_000, max: 1_000_000),
            bounded(y, fallback: style.y, min: -1_000_000, max: 1_000_000)
        )
    }

    private func cornerRadius(style: VisualLayerStyle, animation: AnimationState) -> HyperFrameCornerRadiusBridge {
        let animated = animation.cornerRadius.isFinite ? animation.cornerRadius : nil
        let base = number(style.extra["cornerRadius"], fallback: 0)
        return HyperFrameCornerRadiusBridge(
            topLeft: animated ?? number(style.extra["cornerRadiusTopLeft"], fallback: base),
            topRight: animated ?? number(style.extra["cornerRadiusTopRight"], fallback: base),
            bottomRight: animated ?? number(style.extra["cornerRadiusBottomRight"], fallback: base),
            bottomLeft: animated ?? number(style.extra["cornerRadiusBottomLeft"], fallback: base)
        )
    }

    private func normalizedEffects(_ effects: JSONValue?, layerID: String) -> [HyperFrameEffectInstanceBridge] {
        FXRegistry.shared.normalizedEffects(effects, layerID: layerID).map { effect in
            HyperFrameEffectInstanceBridge(
                id: effect.id,
                source: effect.sourceName,
                kind: effect.canonicalName,
                enabled: effect.enabled,
                params: effect.params,
                quality: effect.quality,
                scope: effect.scope,
                passCategory: effect.passCategory,
                diagnostics: effect.diagnostics
            )
        }
    }

    private func compileAnimationTracks(for clip: WorkspaceClip) -> [String: [AnimationFrame]] {
        var tracks: [String: [AnimationFrame]] = [:]
        let style = clip.style
        let defaultEasing = style.motion?.easing ?? "easeOut"
        if let preset = style.motion?.preset, preset != "none" {
            addPresetFrames(&tracks, preset: preset, duration: style.motion?.inDuration ?? 0.35, defaultEasing: defaultEasing)
        }
        if let motionFrames = style.motion?.keyframes {
            for frame in motionFrames {
                addMotionFrame(&tracks, frame: frame, defaultEasing: defaultEasing)
            }
        }
        if let styleKeyframes = style.keyframes {
            for (property, frames) in styleKeyframes {
                for frame in frames {
                    addFrame(&tracks, property: property, time: frame.time, value: frame.value, easing: frame.easing ?? defaultEasing)
                }
            }
        }
        if let animations = style.animations {
            for animation in animations {
                let easing = animation.easing ?? defaultEasing
                if let property = animation.property {
                    for frame in animation.keyframes {
                        addFrame(&tracks, property: property, time: frame.time ?? frame.t, value: frame.value, easing: frame.easing ?? easing)
                    }
                } else {
                    for frame in animation.keyframes {
                        addMotionFrame(&tracks, frame: frame, defaultEasing: easing)
                    }
                }
            }
        }
        if let legacyFrames = clip.keyframes {
            for frame in legacyFrames {
                addFrame(&tracks, property: frame.property, time: frame.time, value: frame.value, easing: frame.easing ?? defaultEasing)
            }
        }
        for key in tracks.keys {
            tracks[key]?.sort { $0.time < $1.time }
        }
        return tracks
    }

    private func evaluateAnimation(for clip: WorkspaceClip, localTime: Double) -> AnimationState {
        let tracks = compileAnimationTracks(for: clip)
        let scale = evaluateTrack(tracks["scale"], at: localTime, fallback: 1)
        let outDuration = max(0, clip.style.motion?.outDuration ?? 0)
        let outOpacity = outDuration > 0
            ? easedProgress((clip.duration - localTime) / outDuration, easing: clip.style.motion?.easing)
            : 1
        var state = AnimationState()
        state.x = evaluateTrack(tracks["x"], at: localTime, fallback: .nan)
        state.y = evaluateTrack(tracks["y"], at: localTime, fallback: .nan)
        state.positionX = evaluateTrack(tracks["positionX"], at: localTime, fallback: .nan)
        state.positionY = evaluateTrack(tracks["positionY"], at: localTime, fallback: .nan)
        state.centerX = evaluateTrack(tracks["centerX"], at: localTime, fallback: .nan)
        state.centerY = evaluateTrack(tracks["centerY"], at: localTime, fallback: .nan)
        state.opacity = evaluateTrack(tracks["opacity"], at: localTime, fallback: 1) * outOpacity
        state.translateX = evaluateTrack(tracks["translateX"], at: localTime, fallback: 0)
        state.translateY = evaluateTrack(tracks["translateY"], at: localTime, fallback: 0)
        state.scaleX = evaluateTrack(tracks["scaleX"], at: localTime, fallback: scale)
        state.scaleY = evaluateTrack(tracks["scaleY"], at: localTime, fallback: scale)
        state.rotation = evaluateTrack(tracks["rotation"], at: localTime, fallback: 0)
        state.skewX = evaluateTrack(tracks["skewX"], at: localTime, fallback: 0)
        state.skewY = evaluateTrack(tracks["skewY"], at: localTime, fallback: 0)
        state.cornerRadius = evaluateTrack(tracks["cornerRadius"], at: localTime, fallback: .nan)
        state.blur = evaluateTrack(tracks["blur"], at: localTime, fallback: .nan)
        state.brightness = evaluateTrack(tracks["brightness"], at: localTime, fallback: .nan)
        state.contrast = evaluateTrack(tracks["contrast"], at: localTime, fallback: .nan)
        state.saturation = evaluateTrack(tracks["saturation"], at: localTime, fallback: .nan)
        state.exposure = evaluateTrack(tracks["exposure"], at: localTime, fallback: .nan)
        state.hue = evaluateTrack(tracks["hue"], at: localTime, fallback: .nan)
        state.grayscale = evaluateTrack(tracks["grayscale"], at: localTime, fallback: .nan)
        state.sepia = evaluateTrack(tracks["sepia"], at: localTime, fallback: .nan)
        state.invert = evaluateTrack(tracks["invert"], at: localTime, fallback: .nan)
        return state
    }

    private func addMotionFrame(_ tracks: inout [String: [AnimationFrame]], frame: MotionKeyframe, defaultEasing: String?) {
        let time = frame.time ?? frame.t
        let easing = frame.easing ?? defaultEasing
        addFrame(&tracks, property: "x", time: time, value: frame.x, easing: easing)
        addFrame(&tracks, property: "y", time: time, value: frame.y, easing: easing)
        addFrame(&tracks, property: "positionX", time: time, value: frame.positionX, easing: easing)
        addFrame(&tracks, property: "positionY", time: time, value: frame.positionY, easing: easing)
        addFrame(&tracks, property: "centerX", time: time, value: frame.centerX, easing: easing)
        addFrame(&tracks, property: "centerY", time: time, value: frame.centerY, easing: easing)
        addFrame(&tracks, property: "opacity", time: time, value: frame.opacity, easing: easing)
        addFrame(&tracks, property: "translateX", time: time, value: frame.translateX, easing: easing)
        addFrame(&tracks, property: "translateY", time: time, value: frame.translateY, easing: easing)
        addFrame(&tracks, property: "scale", time: time, value: frame.scale, easing: easing)
        addFrame(&tracks, property: "scaleX", time: time, value: frame.scaleX, easing: easing)
        addFrame(&tracks, property: "scaleY", time: time, value: frame.scaleY, easing: easing)
        addFrame(&tracks, property: "rotation", time: time, value: frame.rotation, easing: easing)
        addFrame(&tracks, property: "skewX", time: time, value: frame.skewX, easing: easing)
        addFrame(&tracks, property: "skewY", time: time, value: frame.skewY, easing: easing)
    }

    private func addPresetFrames(_ tracks: inout [String: [AnimationFrame]], preset: String, duration: Double, defaultEasing: String?) {
        let d = max(0.001, duration == 0 ? 0.35 : duration)
        switch preset {
        case "fade":
            addPresetFrame(&tracks, time: 0, values: ["opacity": 0], defaultEasing: defaultEasing)
            addPresetFrame(&tracks, time: d, values: ["opacity": 1], defaultEasing: defaultEasing)
        case "pop":
            addPresetFrame(&tracks, time: 0, values: ["opacity": 0, "scaleX": 0.82, "scaleY": 0.82], defaultEasing: defaultEasing)
            addPresetFrame(&tracks, time: d, values: ["opacity": 1, "scaleX": 1, "scaleY": 1], defaultEasing: defaultEasing)
        case "pop-up-spin", "popUpSpin":
            addPresetFrame(&tracks, time: 0, values: ["opacity": 0, "scaleX": 0.18, "scaleY": 0.18, "translateY": 90, "rotation": -540], defaultEasing: defaultEasing)
            addPresetFrame(&tracks, time: d * 0.76, values: ["opacity": 1, "scaleX": 1.08, "scaleY": 1.08, "translateY": 0, "rotation": 8], easing: "easeOutBack", defaultEasing: defaultEasing)
            addPresetFrame(&tracks, time: d, values: ["opacity": 1, "scaleX": 1, "scaleY": 1, "translateY": 0, "rotation": 0], easing: "easeOut", defaultEasing: defaultEasing)
        case "bounce-in", "bounceIn":
            addPresetFrame(&tracks, time: 0, values: ["opacity": 0, "scaleX": 0.18, "scaleY": 0.18, "translateY": 300, "rotation": 0], defaultEasing: defaultEasing)
            addPresetFrame(&tracks, time: d * 0.49, values: ["opacity": 1, "scaleX": 1.1, "scaleY": 1.1, "translateY": 0, "rotation": -2], easing: "easeOutBack", defaultEasing: defaultEasing)
            addPresetFrame(&tracks, time: d * 0.64, values: ["opacity": 1, "scaleX": 0.96, "scaleY": 0.96, "translateY": 0, "rotation": 1.4], easing: "easeOut", defaultEasing: defaultEasing)
            addPresetFrame(&tracks, time: d * 0.79, values: ["opacity": 1, "scaleX": 1.025, "scaleY": 1.025, "translateY": 0, "rotation": -0.65], easing: "easeOut", defaultEasing: defaultEasing)
            addPresetFrame(&tracks, time: d, values: ["opacity": 1, "scaleX": 1, "scaleY": 1, "translateY": 0, "rotation": 0], easing: "easeOut", defaultEasing: defaultEasing)
        case "fade-up", "fadeUp":
            addPresetFrame(&tracks, time: 0, values: ["opacity": 0, "translateY": 72], defaultEasing: defaultEasing)
            addPresetFrame(&tracks, time: d, values: ["opacity": 1, "translateY": 0], defaultEasing: defaultEasing)
        case "slide-left":
            addPresetFrame(&tracks, time: 0, values: ["opacity": 0, "translateX": 96], defaultEasing: defaultEasing)
            addPresetFrame(&tracks, time: d, values: ["opacity": 1, "translateX": 0], defaultEasing: defaultEasing)
        case "slide-right":
            addPresetFrame(&tracks, time: 0, values: ["opacity": 0, "translateX": -96], defaultEasing: defaultEasing)
            addPresetFrame(&tracks, time: d, values: ["opacity": 1, "translateX": 0], defaultEasing: defaultEasing)
        case "slide-up":
            addPresetFrame(&tracks, time: 0, values: ["opacity": 0, "translateY": 96], defaultEasing: defaultEasing)
            addPresetFrame(&tracks, time: d, values: ["opacity": 1, "translateY": 0], defaultEasing: defaultEasing)
        case "slide-down":
            addPresetFrame(&tracks, time: 0, values: ["opacity": 0, "translateY": -96], defaultEasing: defaultEasing)
            addPresetFrame(&tracks, time: d, values: ["opacity": 1, "translateY": 0], defaultEasing: defaultEasing)
        default:
            break
        }
    }

    private func addPresetFrame(_ tracks: inout [String: [AnimationFrame]], time: Double, values: [String: Double], easing: String? = nil, defaultEasing: String?) {
        for (property, value) in values {
            addFrame(&tracks, property: property, time: time, value: value, easing: easing ?? defaultEasing)
        }
    }

    private func addFrame(_ tracks: inout [String: [AnimationFrame]], property: String, time: Double?, value: Double?, easing: String?) {
        guard let time, let value, time.isFinite, value.isFinite else { return }
        let key = normalizedAnimationProperty(property)
        tracks[key, default: []].append(AnimationFrame(time: time, value: value, easing: easing))
    }

    private func evaluateTrack(_ frames: [AnimationFrame]?, at time: Double, fallback: Double) -> Double {
        guard let frames, !frames.isEmpty else { return fallback }
        if time <= frames[0].time { return frames[0].value }
        guard let last = frames.last else { return fallback }
        if time >= last.time { return last.value }
        for index in 1..<frames.count {
            let previous = frames[index - 1]
            let next = frames[index]
            guard time <= next.time else { continue }
            let span = max(0.0001, next.time - previous.time)
            let progress = easedProgress((time - previous.time) / span, easing: next.easing ?? previous.easing)
            return previous.value + (next.value - previous.value) * progress
        }
        return fallback
    }

    private func easedProgress(_ value: Double, easing: String?) -> Double {
        let t = clamp01(value, fallback: 0)
        guard let easing else { return t }
        switch easing {
        case "linear": return t
        case "easeIn": return t * t * t
        case "easeOut": return 1 - pow(1 - t, 3)
        case "easeInOut", "cubic-bezier(0.42, 0, 0.58, 1)":
            return t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
        case "easeOutBack", "backOut":
            let c1 = 1.70158
            let c3 = c1 + 1
            return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2)
        case "easeInBack", "backIn":
            let c1 = 1.70158
            let c3 = c1 + 1
            return c3 * t * t * t - c1 * t * t
        case "easeInOutBack", "backInOut":
            let c1 = 1.70158
            let c2 = c1 * 1.525
            return t < 0.5
                ? (pow(2 * t, 2) * ((c2 + 1) * 2 * t - c2)) / 2
                : (pow(2 * t - 2, 2) * ((c2 + 1) * (t * 2 - 2) + c2) + 2) / 2
        default:
            return 1 - pow(1 - t, 3)
        }
    }

    private func normalizedAnimationProperty(_ property: String) -> String {
        switch property {
        case "x": return "positionX"
        case "y": return "positionY"
        case "positionX": return "positionX"
        case "positionY": return "positionY"
        case "left": return "x"
        case "top": return "y"
        case "centerX", "cx": return "centerX"
        case "centerY", "cy": return "centerY"
        case "tx", "translate", "translateX": return "translateX"
        case "ty", "translateY": return "translateY"
        case "scale": return "scale"
        case "scaleX": return "scaleX"
        case "scaleY": return "scaleY"
        case "rotate": return "rotation"
        case "rotation": return "rotation"
        case "opacity": return "opacity"
        case "skewX": return "skewX"
        case "skewY": return "skewY"
        case "radius": return "cornerRadius"
        case "cornerRadius": return "cornerRadius"
        case "blur": return "blur"
        case "brightness": return "brightness"
        case "contrast": return "contrast"
        case "saturate": return "saturation"
        case "saturation": return "saturation"
        case "exposure": return "exposure"
        case "hue": return "hue"
        case "grayscale": return "grayscale"
        case "sepia": return "sepia"
        case "invert": return "invert"
        default: return property
        }
    }

    private func orderedTracks(_ tracks: [WorkspaceTrack]) -> [WorkspaceTrack] {
        tracks
    }

    private func animatedFilters(style: VisualLayerStyle, animation: AnimationState) -> JSONValue? {
        var filters = style.filters?.objectValue ?? [:]
        let exposure = animatedOrBase(animation.exposure, base: number(filters["exposure"], fallback: 0))
        filters["brightness"] = .number(max(0, animatedOrBase(animation.brightness, base: number(filters["brightness"], fallback: 1)) * pow(2, exposure)))
        filters["contrast"] = .number(max(0, animatedOrBase(animation.contrast, base: number(filters["contrast"], fallback: 1))))
        filters["saturation"] = .number(max(0, animatedOrBase(animation.saturation, base: number(filters["saturation"], fallback: 1))))
        filters["exposure"] = .number(exposure)
        filters["hue"] = .number(animatedOrBase(animation.hue, base: number(filters["hue"], fallback: 0)))
        filters["blur"] = .number(max(0, animatedOrBase(animation.blur, base: number(filters["blur"], fallback: 0))))
        filters["grayscale"] = .number(clamp01(animatedOrBase(animation.grayscale, base: number(filters["grayscale"], fallback: 0)), fallback: 0))
        filters["sepia"] = .number(clamp01(animatedOrBase(animation.sepia, base: number(filters["sepia"], fallback: 0)), fallback: 0))
        filters["invert"] = .number(clamp01(animatedOrBase(animation.invert, base: number(filters["invert"], fallback: 0)), fallback: 0))
        return .object(filters)
    }

    private func animatedOrBase(_ animated: Double, base: Double) -> Double {
        animated.isFinite ? animated : base
    }

    private func clamp01(_ value: Double, fallback: Double) -> Double {
        let next = value.isFinite ? value : fallback
        return min(1, max(0, next))
    }

    private func bounded(_ value: Double, fallback: Double, min lower: Double, max upper: Double) -> Double {
        let next = value.isFinite ? value : fallback
        return Swift.min(upper, Swift.max(lower, next))
    }

    private func number(_ value: JSONValue?, fallback: Double) -> Double {
        guard let value else { return fallback }
        if case .number(let number) = value { return number }
        if case .string(let string) = value, let number = Double(string) { return number }
        return fallback
    }
}
