import Foundation

enum FXPassCategory: String, Hashable {
    case sourceResolve
    case preTransform
    case transform
    case postTransform
    case mask
    case composite
    case adjustment
    case transition
    case temporal
    case audioReactive
}

enum FXParameterKind: String, Hashable {
    case boolean
    case number
    case string
}

struct FXParameterSchema: Hashable {
    let name: String
    let kind: FXParameterKind
    let defaultValue: JSONValue?
    let required: Bool
    let min: Double?
    let max: Double?
    let allowedValues: Set<String>

    init(
        _ name: String,
        kind: FXParameterKind,
        defaultValue: JSONValue? = nil,
        required: Bool = false,
        min: Double? = nil,
        max: Double? = nil,
        allowedValues: Set<String> = []
    ) {
        self.name = name
        self.kind = kind
        self.defaultValue = defaultValue
        self.required = required
        self.min = min
        self.max = max
        self.allowedValues = allowedValues
    }
}

struct FXDefinition: Hashable {
    let canonicalName: String
    let aliases: Set<String>
    let version: Int
    let category: String
    let passCategory: FXPassCategory
    let parameters: [FXParameterSchema]
    let requiresTemporalSampling: Bool
    let sourceRequirement: String
    let previewQualityPolicy: String
    let exportQualityPolicy: String
    let platformCapabilityKey: String
}

struct NormalizedFXDefinitionResult: Hashable {
    let id: String
    let sourceName: String
    let canonicalName: String
    let enabled: Bool
    let params: JSONValue
    let quality: String
    let scope: String
    let passCategory: FXPassCategory
    let definition: FXDefinition?
    let diagnostics: [UnitedGateDiagnostic]
}

struct FXRegistry {
    static let shared = FXRegistry()

    let definitions: [String: FXDefinition]
    private let aliases: [String: String]

    private init() {
        let entries = [
            FXDefinition(
                canonicalName: "motionTile",
                aliases: ["tile", "mirrorTile", "edgeRepeat"],
                version: 1,
                category: "sampler",
                passCategory: .preTransform,
                parameters: [
                    .init("enabled", kind: .boolean, defaultValue: .bool(true)),
                    .init("mode", kind: .string, defaultValue: .string("mirror"), allowedValues: ["mirror", "repeat", "clamp"]),
                    .init("expansionX", kind: .number, defaultValue: .number(1), min: 1, max: 64),
                    .init("expansionY", kind: .number, defaultValue: .number(1), min: 1, max: 64)
                ],
                requiresTemporalSampling: false,
                sourceRequirement: "source-texture",
                previewQualityPolicy: "same-meaning-lower-budget-allowed",
                exportQualityPolicy: "full-quality",
                platformCapabilityKey: "supportsMotionTile"
            ),
            FXDefinition(
                canonicalName: "motionBlur",
                aliases: ["transformMotionBlur", "directionalMotionBlur"],
                version: 1,
                category: "temporal",
                passCategory: .temporal,
                parameters: [
                    .init("enabled", kind: .boolean, defaultValue: .bool(true)),
                    .init("mode", kind: .string, defaultValue: .string("transform"), allowedValues: ["transform"]),
                    .init("samples", kind: .number, defaultValue: .number(8), min: 2, max: 64),
                    .init("shutterAngle", kind: .number, defaultValue: .number(180), min: 0, max: 1440),
                    .init("shutterPhase", kind: .number, defaultValue: .number(-90), min: -720, max: 720),
                    .init("amount", kind: .number, defaultValue: .number(1), min: 0, max: 10),
                    .init("sampleCurve", kind: .string, defaultValue: .string("centerWeighted"), allowedValues: ["uniform", "centerWeighted", "filmic"])
                ],
                requiresTemporalSampling: true,
                sourceRequirement: "frame-descriptor-samples",
                previewQualityPolicy: "lower-sample-count-with-same-shutter",
                exportQualityPolicy: "full-sample-count",
                platformCapabilityKey: "supportsMotionBlur"
            ),
            FXDefinition(
                canonicalName: "radialBlur",
                aliases: ["radialMotionBlur", "spinBlur", "swirlBlur"],
                version: 1,
                category: "filter",
                passCategory: .postTransform,
                parameters: [
                    .init("enabled", kind: .boolean, defaultValue: .bool(true)),
                    .init("mode", kind: .string, defaultValue: .string("spin"), allowedValues: ["radial", "spin", "zoom", "spiral"]),
                    .init("samples", kind: .number, defaultValue: .number(24), min: 2, max: 96),
                    .init("amount", kind: .number, defaultValue: .number(1), min: 0, max: 10),
                    .init("centerX", kind: .number, defaultValue: .number(0.5), min: -4, max: 4),
                    .init("centerY", kind: .number, defaultValue: .number(0.5), min: -4, max: 4),
                    .init("angleDegrees", kind: .number, defaultValue: .number(18), min: -1440, max: 1440),
                    .init("zoomSpread", kind: .number, defaultValue: .number(0.08), min: -4, max: 4),
                    .init("radialSpread", kind: .number, defaultValue: .number(0.08), min: -4, max: 4),
                    .init("sampleCurve", kind: .string, defaultValue: .string("centerWeighted"), allowedValues: ["uniform", "centerWeighted", "filmic"])
                ],
                requiresTemporalSampling: false,
                sourceRequirement: "intermediate-texture",
                previewQualityPolicy: "same-meaning-lower-sample-count-allowed",
                exportQualityPolicy: "full-sample-count",
                platformCapabilityKey: "supportsRadialBlur"
            ),
            FXDefinition(
                canonicalName: "zoomBlur",
                aliases: [],
                version: 1,
                category: "filter",
                passCategory: .postTransform,
                parameters: [
                    .init("enabled", kind: .boolean, defaultValue: .bool(true)),
                    .init("zoomSpread", kind: .number, defaultValue: .number(0.08), min: -4, max: 4),
                    .init("samples", kind: .number, defaultValue: .number(24), min: 2, max: 96),
                    .init("decay", kind: .number, defaultValue: .number(1), min: 0, max: 10),
                    .init("opacity", kind: .number, defaultValue: .number(1), min: 0, max: 1.5),
                    .init("chromaticFringe", kind: .number, defaultValue: .number(0), min: 0, max: 0.05),
                    .init("quality", kind: .string, defaultValue: .string("auto"), allowedValues: ["auto", "preview", "export"])
                ],
                requiresTemporalSampling: false,
                sourceRequirement: "intermediate-texture",
                previewQualityPolicy: "same-meaning-lower-sample-count-allowed",
                exportQualityPolicy: "full-sample-count",
                platformCapabilityKey: "supportsZoomBlur"
            ),
            FXDefinition(
                canonicalName: "spiralEchoBlur",
                aliases: ["spiralBlur"],
                version: 1,
                category: "filter",
                passCategory: .postTransform,
                parameters: [
                    .init("enabled", kind: .boolean, defaultValue: .bool(true)),
                    .init("angleSpread", kind: .number, defaultValue: .number(720), min: -4320, max: 4320),
                    .init("zoomSpread", kind: .number, defaultValue: .number(0.8), min: -6, max: 6),
                    .init("radialSpread", kind: .number, defaultValue: .number(0), min: -4, max: 4),
                    .init("samples", kind: .number, defaultValue: .number(24), min: 2, max: 96),
                    .init("decay", kind: .number, defaultValue: .number(1.35), min: 0, max: 10),
                    .init("shutter", kind: .number, defaultValue: .number(1), min: 0, max: 10),
                    .init("opacity", kind: .number, defaultValue: .number(0.9), min: 0, max: 1.5),
                    .init("blendMode", kind: .string, defaultValue: .string("source-over"), allowedValues: ["source-over", "screen", "lighter"]),
                    .init("chromaticFringe", kind: .number, defaultValue: .number(0), min: 0, max: 0.05),
                    .init("quality", kind: .string, defaultValue: .string("auto"), allowedValues: ["auto", "preview", "export"])
                ],
                requiresTemporalSampling: false,
                sourceRequirement: "intermediate-texture",
                previewQualityPolicy: "same-meaning-lower-sample-count-allowed",
                exportQualityPolicy: "full-sample-count",
                platformCapabilityKey: "supportsSpiralEchoBlur"
            ),
            FXDefinition(
                canonicalName: "gaussianBlur",
                aliases: ["blur"],
                version: 1,
                category: "filter",
                passCategory: .postTransform,
                parameters: [
                    .init("enabled", kind: .boolean, defaultValue: .bool(true)),
                    .init("radius", kind: .number, defaultValue: .number(0), min: 0, max: 256)
                ],
                requiresTemporalSampling: false,
                sourceRequirement: "intermediate-texture",
                previewQualityPolicy: "same-radius-lower-kernel-budget-allowed",
                exportQualityPolicy: "full-radius-kernel",
                platformCapabilityKey: "supportsGaussianBlur"
            ),
            FXDefinition(
                canonicalName: "glow",
                aliases: ["outerGlow", "bloom"],
                version: 1,
                category: "filter",
                passCategory: .postTransform,
                parameters: [
                    .init("enabled", kind: .boolean, defaultValue: .bool(true)),
                    .init("radius", kind: .number, defaultValue: .number(24), min: 0, max: 256),
                    .init("intensity", kind: .number, defaultValue: .number(1), min: 0, max: 20),
                    .init("threshold", kind: .number, defaultValue: .number(0.7), min: 0, max: 1)
                ],
                requiresTemporalSampling: false,
                sourceRequirement: "intermediate-texture",
                previewQualityPolicy: "same-threshold-lower-budget-allowed",
                exportQualityPolicy: "full-quality",
                platformCapabilityKey: "supportsGlow"
            ),
            FXDefinition(
                canonicalName: "colorCorrection",
                aliases: ["colorAdjust", "colorGrade"],
                version: 1,
                category: "adjustment",
                passCategory: .adjustment,
                parameters: [
                    .init("enabled", kind: .boolean, defaultValue: .bool(true)),
                    .init("brightness", kind: .number, defaultValue: .number(0), min: -1, max: 1),
                    .init("contrast", kind: .number, defaultValue: .number(1), min: 0, max: 4),
                    .init("saturation", kind: .number, defaultValue: .number(1), min: 0, max: 4),
                    .init("temperature", kind: .number, defaultValue: .number(0), min: -1, max: 1)
                ],
                requiresTemporalSampling: false,
                sourceRequirement: "intermediate-texture",
                previewQualityPolicy: "full-parameter-meaning",
                exportQualityPolicy: "full-parameter-meaning",
                platformCapabilityKey: "supportsColorCorrection"
            ),
            FXDefinition(
                canonicalName: "clipToRoundedBounds",
                aliases: ["roundedMask", "cornerMask"],
                version: 1,
                category: "mask",
                passCategory: .mask,
                parameters: [
                    .init("enabled", kind: .boolean, defaultValue: .bool(true)),
                    .init("radius", kind: .number, defaultValue: .number(0), min: 0, max: 4096)
                ],
                requiresTemporalSampling: false,
                sourceRequirement: "layer-alpha-mask",
                previewQualityPolicy: "full-geometry",
                exportQualityPolicy: "full-geometry",
                platformCapabilityKey: "supportsMask"
            ),
            FXDefinition(
                canonicalName: "borderComposite",
                aliases: ["border", "stroke"],
                version: 1,
                category: "composite",
                passCategory: .composite,
                parameters: [
                    .init("enabled", kind: .boolean, defaultValue: .bool(true)),
                    .init("width", kind: .number, defaultValue: .number(0), min: 0, max: 4096),
                    .init("color", kind: .string, defaultValue: .string("#FFFFFF")),
                    .init("opacity", kind: .number, defaultValue: .number(1), min: 0, max: 1)
                ],
                requiresTemporalSampling: false,
                sourceRequirement: "layer-bounds",
                previewQualityPolicy: "full-geometry",
                exportQualityPolicy: "full-geometry",
                platformCapabilityKey: "supportsBorderComposite"
            ),
            FXDefinition(
                canonicalName: "dropShadow",
                aliases: ["shadow"],
                version: 1,
                category: "composite",
                passCategory: .composite,
                parameters: [
                    .init("enabled", kind: .boolean, defaultValue: .bool(true)),
                    .init("offsetX", kind: .number, defaultValue: .number(0), min: -4096, max: 4096),
                    .init("offsetY", kind: .number, defaultValue: .number(0), min: -4096, max: 4096),
                    .init("blur", kind: .number, defaultValue: .number(0), min: 0, max: 1024),
                    .init("spread", kind: .number, defaultValue: .number(0), min: -1024, max: 1024),
                    .init("color", kind: .string, defaultValue: .string("#000000")),
                    .init("opacity", kind: .number, defaultValue: .number(1), min: 0, max: 1)
                ],
                requiresTemporalSampling: false,
                sourceRequirement: "layer-alpha-mask",
                previewQualityPolicy: "full-geometry",
                exportQualityPolicy: "full-geometry",
                platformCapabilityKey: "supportsDropShadow"
            )
        ]

        definitions = Dictionary(uniqueKeysWithValues: entries.map { ($0.canonicalName, $0) })
        aliases = entries.reduce(into: [String: String]()) { result, definition in
            result[definition.canonicalName] = definition.canonicalName
            for alias in definition.aliases {
                result[alias] = definition.canonicalName
            }
        }
    }

    func definition(for effectName: String) -> FXDefinition? {
        guard let canonicalName = aliases[effectName] else { return nil }
        return definitions[canonicalName]
    }

    func normalizedEffects(_ effects: JSONValue?, layerID: String) -> [NormalizedFXDefinitionResult] {
        guard case .object(let object) = effects else { return [] }
        return object.keys.sorted().compactMap { key in
            guard let raw = object[key] else { return nil }
            return normalize(effectName: key, rawValue: raw, layerID: layerID)
        }
    }

    func validateEffects(_ effects: JSONValue?, clipID: String) -> [UnitedGateDiagnostic] {
        guard case .object(let object) = effects else { return [] }
        return object.keys.sorted().flatMap { key -> [UnitedGateDiagnostic] in
            guard let raw = object[key] else { return [] }
            return normalize(effectName: key, rawValue: raw, layerID: clipID).diagnostics
        }
    }

    private func normalize(effectName: String, rawValue: JSONValue, layerID: String) -> NormalizedFXDefinitionResult {
        guard let definition = definition(for: effectName) else {
            return NormalizedFXDefinitionResult(
                id: "\(layerID):\(effectName)",
                sourceName: effectName,
                canonicalName: effectName,
                enabled: rawValue.objectValue?["enabled"]?.boolValue ?? true,
                params: rawValue,
                quality: "auto",
                scope: "node",
                passCategory: .postTransform,
                definition: nil,
                diagnostics: [
                    UnitedGateDiagnostic(
                        severity: .warning,
                        code: "unknown-effect-preserved",
                        message: "Clip \(layerID) has unknown style.effects.\(effectName); it is preserved but cannot render until registered in FXRegistry."
                    )
                ]
            )
        }

        let object = rawValue.objectValue ?? [:]
        var normalized = object
        applyCanonicalAliases(definition: definition, sourceName: effectName, values: &normalized)
        var diagnostics: [UnitedGateDiagnostic] = []
        for parameter in definition.parameters {
            if normalized[parameter.name] == nil, let defaultValue = parameter.defaultValue {
                normalized[parameter.name] = defaultValue
            }
            guard let value = normalized[parameter.name] else {
                if parameter.required {
                    diagnostics.append(.init(
                        severity: .blocked,
                        code: "blocked-invalid-fx-schema",
                        message: "Clip \(layerID) style.effects.\(effectName).\(parameter.name) is required."
                    ))
                }
                continue
            }
            diagnostics.append(contentsOf: validate(value: value, parameter: parameter, effectName: effectName, clipID: layerID))
        }
        let enabled = normalized["enabled"]?.boolValue ?? true
        let quality = normalized["quality"]?.stringValue ?? "auto"
        let scope = normalized["scope"]?.stringValue ?? "node"
        return NormalizedFXDefinitionResult(
            id: "\(layerID):\(definition.canonicalName)",
            sourceName: effectName,
            canonicalName: definition.canonicalName,
            enabled: enabled,
            params: .object(normalized),
            quality: quality,
            scope: scope,
            passCategory: definition.passCategory,
            definition: definition,
            diagnostics: diagnostics
        )
    }

    private func applyCanonicalAliases(definition: FXDefinition, sourceName: String, values: inout [String: JSONValue]) {
        switch definition.canonicalName {
        case "motionTile":
            if values["expansionX"] == nil {
                values["expansionX"] = values["outputWidth"] ?? values["expansion"]
            }
            if values["expansionY"] == nil {
                values["expansionY"] = values["outputHeight"] ?? values["expansion"]
            }
        case "motionBlur":
            if values["samples"]?.stringValue == "auto" {
                values["samples"] = .number(8)
            }
            if values["amount"] == nil {
                values["amount"] = values["strength"]
            }
            if values["shutterAngle"] == nil, let shutter = values["shutter"]?.numberValue {
                values["shutterAngle"] = .number(shutter * 180)
            }
            if values["mode"] == nil {
                values["mode"] = .string("transform")
            }
            if let activeRange = values["activeRange"]?.objectValue {
                if values["activeFrom"] == nil { values["activeFrom"] = activeRange["start"] }
                if values["activeTo"] == nil { values["activeTo"] = activeRange["end"] }
            }
        case "radialBlur":
            if values["samples"]?.stringValue == "auto" {
                values["samples"] = .number(24)
            }
            if values["amount"] == nil {
                values["amount"] = values["strength"] ?? values["intensity"]
            }
            if values["centerX"] == nil {
                values["centerX"] = values["originX"] ?? values["pivotX"]
            }
            if values["centerY"] == nil {
                values["centerY"] = values["originY"] ?? values["pivotY"]
            }
            if values["angleDegrees"] == nil {
                values["angleDegrees"] = values["spinDegrees"] ?? values["rotationDegrees"] ?? values["angle"]
            }
            if values["mode"] == nil {
                switch sourceName {
                case "zoomBlur":
                    values["mode"] = .string("zoom")
                case "spiralBlur", "spiralEchoBlur", "swirlBlur":
                    values["mode"] = .string("spiral")
                case "radialBlur", "radialMotionBlur":
                    values["mode"] = .string("radial")
                default:
                    values["mode"] = .string("spin")
                }
            }
            if let activeRange = values["activeRange"]?.objectValue {
                if values["activeFrom"] == nil { values["activeFrom"] = activeRange["start"] }
                if values["activeTo"] == nil { values["activeTo"] = activeRange["end"] }
            }
        case "zoomBlur":
            if values["samples"]?.stringValue == "auto" {
                values["samples"] = .number(24)
            }
            if values["mode"] == nil {
                values["mode"] = .string("zoom")
            }
            applyCenterAliases(values: &values)
        case "spiralEchoBlur":
            if values["samples"]?.stringValue == "auto" {
                values["samples"] = .number(24)
            }
            if values["mode"] == nil {
                values["mode"] = .string("spiral")
            }
            if values["angleDegrees"] == nil {
                values["angleDegrees"] = values["angleSpread"]
            }
            applyCenterAliases(values: &values)
        default:
            break
        }
    }

    private func applyCenterAliases(values: inout [String: JSONValue]) {
        if let center = values["center"]?.objectValue {
            if values["centerX"] == nil { values["centerX"] = center["x"] }
            if values["centerY"] == nil { values["centerY"] = center["y"] }
        }
    }

    private func validate(value: JSONValue, parameter: FXParameterSchema, effectName: String, clipID: String) -> [UnitedGateDiagnostic] {
        switch parameter.kind {
        case .boolean:
            guard value.boolValue != nil else {
                return [invalidType(parameter: parameter, effectName: effectName, clipID: clipID, expected: "boolean")]
            }
        case .number:
            guard let number = value.numberValue, number.isFinite else {
                return [invalidType(parameter: parameter, effectName: effectName, clipID: clipID, expected: "finite number")]
            }
            if let min = parameter.min, number < min {
                return [invalidRange(parameter: parameter, effectName: effectName, clipID: clipID, rule: ">= \(min)")]
            }
            if let max = parameter.max, number > max {
                return [invalidRange(parameter: parameter, effectName: effectName, clipID: clipID, rule: "<= \(max)")]
            }
        case .string:
            guard let string = value.stringValue else {
                return [invalidType(parameter: parameter, effectName: effectName, clipID: clipID, expected: "string")]
            }
            if !parameter.allowedValues.isEmpty, !parameter.allowedValues.contains(string) {
                let allowedValues = parameter.allowedValues.sorted().joined(separator: ", ")
                return [UnitedGateDiagnostic(
                    severity: .blocked,
                    code: "blocked-invalid-fx-schema",
                    message: "Clip \(clipID) style.effects.\(effectName).\(parameter.name) must be one of \(allowedValues)."
                )]
            }
        }
        return []
    }

    private func invalidType(parameter: FXParameterSchema, effectName: String, clipID: String, expected: String) -> UnitedGateDiagnostic {
        UnitedGateDiagnostic(
            severity: .blocked,
            code: "blocked-invalid-fx-schema",
            message: "Clip \(clipID) style.effects.\(effectName).\(parameter.name) must be \(expected)."
        )
    }

    private func invalidRange(parameter: FXParameterSchema, effectName: String, clipID: String, rule: String) -> UnitedGateDiagnostic {
        UnitedGateDiagnostic(
            severity: .blocked,
            code: "blocked-invalid-fx-schema",
            message: "Clip \(clipID) style.effects.\(effectName).\(parameter.name) must be \(rule)."
        )
    }
}
