import Foundation

enum FXPassSupportState: String, Hashable {
    case supported
    case supportedWithQualityLimit
    case unsupportedDiagnostic
    case blocked
}

struct PlatformFXCapabilities: Hashable {
    let backendName: String
    let supportedEffects: Set<String>
    let qualityLimitedEffects: Set<String>
    let supportsTemporalSampling: Bool
    let supportsIntermediateTextures: Bool
    let preferredAccumulationPixelFormat: String
    let maxTextureSize: Int
    let maxPreviewSamples: Int
    let maxExportSamples: Int

    static let compatibilityRenderer = PlatformFXCapabilities(
        backendName: "quartz-cgcontext-cvpixelbuffer-compatibility",
        supportedEffects: [],
        qualityLimitedEffects: [],
        supportsTemporalSampling: false,
        supportsIntermediateTextures: false,
        preferredAccumulationPixelFormat: "bgra8Unorm-diagnostic-fallback",
        maxTextureSize: 16_384,
        maxPreviewSamples: 1,
        maxExportSamples: 1
    )

    static let macOSMetalPlanned = PlatformFXCapabilities(
        backendName: "metal-rendergraph-fx-runtime",
        supportedEffects: [
            "motionTile",
            "radialBlur",
            "zoomBlur",
            "spiralEchoBlur",
            "gaussianBlur",
            "glow",
            "colorCorrection",
            "clipToRoundedBounds",
            "borderComposite",
            "dropShadow"
        ],
        qualityLimitedEffects: ["motionBlur"],
        supportsTemporalSampling: true,
        supportsIntermediateTextures: true,
        preferredAccumulationPixelFormat: "rgba16Float",
        maxTextureSize: 16_384,
        maxPreviewSamples: 8,
        maxExportSamples: 64
    )

    static let macOSNativeRuntime = PlatformFXCapabilities(
        backendName: "macos-native-rendergraph-with-metal-fx-runtime",
        supportedEffects: [
            "motionTile",
            "motionBlur",
            "radialBlur",
            "zoomBlur",
            "spiralEchoBlur",
            "clipToRoundedBounds",
            "borderComposite",
            "dropShadow"
        ],
        qualityLimitedEffects: [],
        supportsTemporalSampling: true,
        supportsIntermediateTextures: true,
        preferredAccumulationPixelFormat: "rgba16Float",
        maxTextureSize: 16_384,
        maxPreviewSamples: 24,
        maxExportSamples: 192
    )

    func supportState(for effect: String, definition: FXDefinition?) -> FXPassSupportState {
        guard definition != nil else { return .unsupportedDiagnostic }
        if supportedEffects.contains(effect) { return .supported }
        if qualityLimitedEffects.contains(effect) { return .supportedWithQualityLimit }
        return .unsupportedDiagnostic
    }
}

struct NormalizedFXInstance: Hashable, Identifiable {
    let id: String
    let clipId: String
    let sourceName: String
    let canonicalName: String
    let enabled: Bool
    let scope: String
    let passCategory: FXPassCategory
    let params: JSONValue
    let sourceRequirement: String
    let temporalSamplePlan: String
    let qualityPolicy: String
    let diagnostics: [UnitedGateDiagnostic]
}

struct FXPassNode: Hashable, Identifiable {
    let id: String
    let clipId: String
    let effectName: String
    let sourceName: String
    let category: FXPassCategory
    let stageIndex: Int
    let input: String
    let output: String
    let status: FXPassSupportState
    let params: JSONValue
    let diagnostics: [UnitedGateDiagnostic]
}

struct FXPassGraphSnapshot: Hashable {
    let revision: String
    let frameIndex: Int
    let time: Double
    let backendName: String
    let capabilities: PlatformFXCapabilities
    let instances: [NormalizedFXInstance]
    let passes: [FXPassNode]
    let diagnostics: [UnitedGateDiagnostic]

    var unsupportedPasses: [FXPassNode] {
        passes.filter { $0.status == .unsupportedDiagnostic || $0.status == .blocked }
    }
}

struct FXPassGraphCompiler {
    private let registry = FXRegistry.shared

    func compile(renderGraph: RenderGraphSnapshot, capabilities: PlatformFXCapabilities) -> FXPassGraphSnapshot {
        var instances: [NormalizedFXInstance] = []
        var passes: [FXPassNode] = []
        var diagnostics = renderGraph.diagnostics
        var stageIndex = 0

        for node in renderGraph.nodes.sorted(by: { $0.zIndex < $1.zIndex }) {
            for effect in node.effects where effect.enabled && Self.isActive(effect: effect, localTime: node.localTime) {
                let definition = registry.definition(for: effect.source)
                    ?? registry.definition(for: effect.kind)
                let category = definition?.passCategory ?? effect.passCategory
                let sourceRequirement = definition?.sourceRequirement ?? "registered-fx-definition"
                let temporalPlan = Self.temporalSamplePlan(effect: effect, definition: definition, capabilities: capabilities)
                let qualityPolicy = definition?.exportQualityPolicy ?? "unsupported"
                let state = capabilities.supportState(for: effect.kind, definition: definition)
                var passDiagnostics: [UnitedGateDiagnostic] = effect.diagnostics

                if state == .unsupportedDiagnostic {
                    passDiagnostics.append(.init(
                        severity: .warning,
                        code: "unsupported-fx-pass",
                        message: "Clip \(node.clipId) effect \(effect.kind) reached FXPassGraph, but backend \(capabilities.backendName) does not declare an executable pass for it."
                    ))
                }
                if state == .blocked {
                    passDiagnostics.append(.init(
                        severity: .blocked,
                        code: "blocked-fx-pass",
                        message: "Clip \(node.clipId) effect \(effect.kind) is blocked for backend \(capabilities.backendName)."
                    ))
                }

                let instance = NormalizedFXInstance(
                    id: effect.id,
                    clipId: node.clipId,
                    sourceName: effect.source,
                    canonicalName: effect.kind,
                    enabled: effect.enabled,
                    scope: effect.scope,
                    passCategory: category,
                    params: effect.params,
                    sourceRequirement: sourceRequirement,
                    temporalSamplePlan: temporalPlan,
                    qualityPolicy: qualityPolicy,
                    diagnostics: passDiagnostics
                )
                instances.append(instance)
                diagnostics.append(contentsOf: passDiagnostics)
                passes.append(FXPassNode(
                    id: "\(effect.id):pass",
                    clipId: node.clipId,
                    effectName: effect.kind,
                    sourceName: effect.source,
                    category: category,
                    stageIndex: stageIndex,
                    input: "\(node.id):texture-in",
                    output: "\(node.id):\(effect.kind):texture-out",
                    status: state,
                    params: effect.params,
                    diagnostics: passDiagnostics
                ))
                stageIndex += 1
            }
        }

        return FXPassGraphSnapshot(
            revision: renderGraph.revision,
            frameIndex: renderGraph.frameIndex,
            time: renderGraph.time,
            backendName: capabilities.backendName,
            capabilities: capabilities,
            instances: instances,
            passes: passes.sorted(by: Self.passSort),
            diagnostics: diagnostics
        )
    }

    private static func temporalSamplePlan(effect: RenderEffect, definition: FXDefinition?, capabilities: PlatformFXCapabilities) -> String {
        guard definition?.requiresTemporalSampling == true else { return "single-frame" }
        let requestedSamples = effect.params.objectValue?["samples"]?.numberValue ?? Double(capabilities.maxPreviewSamples)
        let samples = min(max(1, Int(requestedSamples.rounded())), capabilities.maxExportSamples)
        return capabilities.supportsTemporalSampling
            ? "adaptive-deterministic-\(samples)-samples-\(capabilities.preferredAccumulationPixelFormat)"
            : "unsupported-temporal-sampling"
    }

    private static func isActive(effect: RenderEffect, localTime: Double) -> Bool {
        guard let params = effect.params.objectValue else { return true }
        let activeRange = params["activeRange"]?.objectValue
        let activeFrom = params["activeFrom"]?.numberValue ?? activeRange?["start"]?.numberValue
        let activeTo = params["activeTo"]?.numberValue ?? activeRange?["end"]?.numberValue
        if let activeFrom, localTime < activeFrom {
            return false
        }
        if let activeTo, localTime > activeTo {
            return false
        }
        return true
    }

    private static func passSort(_ left: FXPassNode, _ right: FXPassNode) -> Bool {
        let leftRank = passRank(left.category)
        let rightRank = passRank(right.category)
        if leftRank == rightRank { return left.stageIndex < right.stageIndex }
        return leftRank < rightRank
    }

    private static func passRank(_ category: FXPassCategory) -> Int {
        switch category {
        case .sourceResolve: return 0
        case .preTransform: return 1
        case .transform: return 2
        case .postTransform: return 3
        case .mask: return 4
        case .composite: return 5
        case .adjustment: return 6
        case .transition: return 7
        case .temporal: return 8
        case .audioReactive: return 9
        }
    }
}
