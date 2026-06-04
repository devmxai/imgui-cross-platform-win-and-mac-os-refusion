import Foundation
import SwiftUI

enum LibrarySection: String, CaseIterable {
    case media
    case text
    case audio
    case background
    case shapes

    var title: String {
        switch self {
        case .media: return "Assets"
        case .text: return "Text"
        case .audio: return "Audio"
        case .background: return "Background"
        case .shapes: return "Shapes"
        }
    }
}

enum AlignmentEdge {
    case left
    case top
    case right
    case center
}

enum TimelineAutoScrollMode {
    case smooth
    case page
    case none
}

struct TimelineViewport: Hashable {
    var visibleStartSeconds: Double = 0
    var visibleDurationSeconds: Double = 10
    var autoScrollMode: TimelineAutoScrollMode = .smooth

    func clamped(projectDuration: Double) -> TimelineViewport {
        let duration = max(0.1, projectDuration)
        let visibleDuration = min(max(1, visibleDurationSeconds), duration)
        let maxStart = max(0, duration - visibleDuration)
        return TimelineViewport(
            visibleStartSeconds: min(max(0, visibleStartSeconds), maxStart),
            visibleDurationSeconds: visibleDuration,
            autoScrollMode: autoScrollMode
        )
    }
}

struct DynamicCodingKey: CodingKey, Hashable {
    var stringValue: String
    var intValue: Int?

    init(_ stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(stringValue: String) {
        self.init(stringValue)
    }

    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

enum JSONValue: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

private func decodeUnknownFields<K: CodingKey>(
    from decoder: Decoder,
    excluding knownKeys: Set<String>,
    keyedBy _: K.Type
) throws -> [String: JSONValue] {
    let container = try decoder.container(keyedBy: DynamicCodingKey.self)
    var unknown: [String: JSONValue] = [:]
    for key in container.allKeys where !knownKeys.contains(key.stringValue) {
        unknown[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
    }
    return unknown
}

private func encodeUnknownFields(
    _ extra: [String: JSONValue],
    into encoder: Encoder,
    excluding knownKeys: Set<String>
) throws {
    var container = encoder.container(keyedBy: DynamicCodingKey.self)
    for (key, value) in extra where !knownKeys.contains(key) {
        try container.encode(value, forKey: DynamicCodingKey(key))
    }
}

struct WorkspaceComposition: Codable, Hashable {
    var width: Int
    var height: Int
    var fps: Double
    var durationSeconds: Double
    var extra: [String: JSONValue] = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case width, height, fps, durationSeconds
    }

    init(width: Int, height: Int, fps: Double, durationSeconds: Double, extra: [String: JSONValue] = [:]) {
        self.width = width
        self.height = height
        self.fps = fps
        self.durationSeconds = durationSeconds
        self.extra = extra
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        width = try container.decode(Int.self, forKey: .width)
        height = try container.decode(Int.self, forKey: .height)
        fps = try container.decode(Double.self, forKey: .fps)
        durationSeconds = try container.decode(Double.self, forKey: .durationSeconds)
        extra = try decodeUnknownFields(from: decoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)), keyedBy: CodingKeys.self)
    }

    func encode(to encoder: Encoder) throws {
        try encodeUnknownFields(extra, into: encoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)))
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encode(fps, forKey: .fps)
        try container.encode(durationSeconds, forKey: .durationSeconds)
    }
}

struct AssetManifest: Codable {
    var version: Int
    var updatedAt: String
    var assets: [WorkspaceAsset]
    var extra: [String: JSONValue] = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case version, updatedAt, assets
    }

    init(version: Int, updatedAt: String, assets: [WorkspaceAsset], extra: [String: JSONValue] = [:]) {
        self.version = version
        self.updatedAt = updatedAt
        self.assets = assets
        self.extra = extra
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        assets = try container.decodeIfPresent([WorkspaceAsset].self, forKey: .assets) ?? []
        extra = try decodeUnknownFields(from: decoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)), keyedBy: CodingKeys.self)
    }

    func encode(to encoder: Encoder) throws {
        try encodeUnknownFields(extra, into: encoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)))
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(assets, forKey: .assets)
    }
}

struct WorkspaceAsset: Codable, Identifiable, Hashable {
    var id: String
    var type: String
    var name: String
    var fileName: String
    var path: String
    var size: Int
    var width: Int?
    var height: Int?
    var duration: Double?
    var fps: Double?
    var createdAt: String
    var extra: [String: JSONValue] = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, type, name, fileName, path, size, width, height, duration, fps, createdAt
    }

    init(
        id: String,
        type: String,
        name: String,
        fileName: String,
        path: String,
        size: Int,
        width: Int?,
        height: Int?,
        duration: Double?,
        fps: Double?,
        createdAt: String,
        extra: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.fileName = fileName
        self.path = path
        self.size = size
        self.width = width
        self.height = height
        self.duration = duration
        self.fps = fps
        self.createdAt = createdAt
        self.extra = extra
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        path = try container.decodeIfPresent(String.self, forKey: .path) ?? ""
        size = try container.decodeIfPresent(Int.self, forKey: .size) ?? 0
        width = try container.decodeIfPresent(Int.self, forKey: .width)
        height = try container.decodeIfPresent(Int.self, forKey: .height)
        duration = try container.decodeIfPresent(Double.self, forKey: .duration)
        fps = try container.decodeIfPresent(Double.self, forKey: .fps)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        extra = try decodeUnknownFields(from: decoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)), keyedBy: CodingKeys.self)
    }

    func encode(to encoder: Encoder) throws {
        try encodeUnknownFields(extra, into: encoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)))
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(name, forKey: .name)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(path, forKey: .path)
        try container.encode(size, forKey: .size)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(fps, forKey: .fps)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

struct WorkspaceTimeline: Codable, Hashable {
    var version: Int
    var fps: Double
    var durationSeconds: Double
    var updatedAt: String
    var tracks: [WorkspaceTrack]
    var extra: [String: JSONValue] = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case version, fps, durationSeconds, updatedAt, tracks
    }

    init(version: Int, fps: Double, durationSeconds: Double, updatedAt: String, tracks: [WorkspaceTrack], extra: [String: JSONValue] = [:]) {
        self.version = version
        self.fps = fps
        self.durationSeconds = durationSeconds
        self.updatedAt = updatedAt
        self.tracks = tracks
        self.extra = extra
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        fps = try container.decodeIfPresent(Double.self, forKey: .fps) ?? 30
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds) ?? 1
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
        tracks = try container.decodeIfPresent([WorkspaceTrack].self, forKey: .tracks) ?? []
        extra = try decodeUnknownFields(from: decoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)), keyedBy: CodingKeys.self)
    }

    func encode(to encoder: Encoder) throws {
        try encodeUnknownFields(extra, into: encoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)))
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(fps, forKey: .fps)
        try container.encode(durationSeconds, forKey: .durationSeconds)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(tracks, forKey: .tracks)
    }
}

struct WorkspaceTrack: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var kind: String
    var isHidden: Bool?
    var isMuted: Bool?
    var clips: [WorkspaceClip]
    var extra: [String: JSONValue] = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, kind, isHidden, isMuted, clips
    }

    init(id: String, name: String, kind: String, isHidden: Bool? = nil, isMuted: Bool? = nil, clips: [WorkspaceClip], extra: [String: JSONValue] = [:]) {
        self.id = id
        self.name = name
        self.kind = kind
        self.isHidden = isHidden
        self.isMuted = isMuted
        self.clips = clips
        self.extra = extra
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "image"
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden)
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted)
        clips = try container.decodeIfPresent([WorkspaceClip].self, forKey: .clips) ?? []
        extra = try decodeUnknownFields(from: decoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)), keyedBy: CodingKeys.self)
    }

    func encode(to encoder: Encoder) throws {
        try encodeUnknownFields(extra, into: encoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)))
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(isHidden, forKey: .isHidden)
        try container.encodeIfPresent(isMuted, forKey: .isMuted)
        try container.encode(clips, forKey: .clips)
    }
}

struct WorkspaceClip: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var type: String
    var assetId: String?
    var trackId: String
    var start: Double
    var duration: Double
    var trimIn: Double
    var render: ClipRender?
    var style: VisualLayerStyle
    var text: TextLayerContent?
    var shape: ShapeLayerContent?
    var keyframes: [TimelineKeyframe]?
    var extra: [String: JSONValue] = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, type, assetId, trackId, start, duration, trimIn, render, style, text, shape, keyframes
    }

    init(
        id: String,
        name: String,
        type: String,
        assetId: String?,
        trackId: String,
        start: Double,
        duration: Double,
        trimIn: Double,
        render: ClipRender?,
        style: VisualLayerStyle,
        text: TextLayerContent?,
        shape: ShapeLayerContent?,
        keyframes: [TimelineKeyframe]? = nil,
        extra: [String: JSONValue] = [:]
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.assetId = assetId
        self.trackId = trackId
        self.start = start
        self.duration = duration
        self.trimIn = trimIn
        self.render = render
        self.style = style
        self.text = text
        self.shape = shape
        self.keyframes = keyframes
        self.extra = extra
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? id
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? "image"
        assetId = try container.decodeIfPresent(String.self, forKey: .assetId)
        trackId = try container.decodeIfPresent(String.self, forKey: .trackId) ?? ""
        start = try container.decodeIfPresent(Double.self, forKey: .start) ?? 0
        duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 1
        trimIn = try container.decodeIfPresent(Double.self, forKey: .trimIn) ?? 0
        render = try container.decodeIfPresent(ClipRender.self, forKey: .render)
        style = try container.decodeIfPresent(VisualLayerStyle.self, forKey: .style) ?? .fallback
        text = try container.decodeIfPresent(TextLayerContent.self, forKey: .text)
        shape = try container.decodeIfPresent(ShapeLayerContent.self, forKey: .shape)
        keyframes = try container.decodeIfPresent([TimelineKeyframe].self, forKey: .keyframes)
        extra = try decodeUnknownFields(from: decoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)), keyedBy: CodingKeys.self)
    }

    func encode(to encoder: Encoder) throws {
        try encodeUnknownFields(extra, into: encoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)))
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(assetId, forKey: .assetId)
        try container.encode(trackId, forKey: .trackId)
        try container.encode(start, forKey: .start)
        try container.encode(duration, forKey: .duration)
        try container.encode(trimIn, forKey: .trimIn)
        try container.encodeIfPresent(render, forKey: .render)
        try container.encode(style, forKey: .style)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(shape, forKey: .shape)
        try container.encodeIfPresent(keyframes, forKey: .keyframes)
    }

    var startFrame: Int {
        max(0, Int((start * 30).rounded()))
    }

    var durationFrames: Int {
        max(1, Int((duration * 30).rounded()))
    }
}

struct ClipRender: Codable, Hashable {
    var compositor: String
}

struct ShapeLayerContent: Codable, Hashable {
    var kind: String
}

struct TextLayerContent: Codable, Hashable {
    var content: String
    var fontFamily: String
    var fontSize: Double
    var fontWeight: String
    var color: String
    var align: String
    var extra: [String: JSONValue] = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case content, fontFamily, fontSize, fontWeight, color, align
    }

    init(
        content: String,
        fontFamily: String,
        fontSize: Double,
        fontWeight: String,
        color: String,
        align: String,
        extra: [String: JSONValue] = [:]
    ) {
        self.content = content
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.fontWeight = fontWeight
        self.color = color
        self.align = align
        self.extra = extra
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        fontFamily = try container.decodeIfPresent(String.self, forKey: .fontFamily) ?? "SF Pro Display"
        fontSize = try container.decodeIfPresent(Double.self, forKey: .fontSize) ?? 48
        if let stringWeight = try? container.decode(String.self, forKey: .fontWeight) {
            fontWeight = stringWeight
        } else if let numericWeight = try? container.decode(Double.self, forKey: .fontWeight) {
            fontWeight = numericWeight.rounded() == numericWeight
                ? String(Int(numericWeight))
                : String(numericWeight)
        } else {
            fontWeight = "400"
        }
        color = try container.decodeIfPresent(String.self, forKey: .color) ?? "#111827"
        align = try container.decodeIfPresent(String.self, forKey: .align) ?? "center"
        extra = try decodeUnknownFields(from: decoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)), keyedBy: CodingKeys.self)
    }

    func encode(to encoder: Encoder) throws {
        try encodeUnknownFields(extra, into: encoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)))
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(content, forKey: .content)
        try container.encode(fontFamily, forKey: .fontFamily)
        try container.encode(fontSize, forKey: .fontSize)
        try container.encode(fontWeight, forKey: .fontWeight)
        try container.encode(color, forKey: .color)
        try container.encode(align, forKey: .align)
    }
}

struct TimelineKeyframe: Codable, Hashable {
    var property: String
    var time: Double
    var value: Double
    var easing: String?
}

struct MotionKeyframe: Codable, Hashable {
    var time: Double?
    var t: Double?
    var value: Double?
    var x: Double?
    var y: Double?
    var positionX: Double?
    var positionY: Double?
    var centerX: Double?
    var centerY: Double?
    var opacity: Double?
    var translateX: Double?
    var translateY: Double?
    var scale: Double?
    var scaleX: Double?
    var scaleY: Double?
    var rotation: Double?
    var skewX: Double?
    var skewY: Double?
    var easing: String?
}

struct StylePropertyKeyframe: Codable, Hashable {
    var time: Double
    var value: Double
    var easing: String?
}

struct StyleAnimation: Codable, Hashable {
    var property: String?
    var easing: String?
    var keyframes: [MotionKeyframe]
}

struct MotionStyle: Codable, Hashable {
    var preset: String?
    var inDuration: Double?
    var outDuration: Double?
    var easing: String?
    var keyframes: [MotionKeyframe]?
}

struct VisualLayerStyle: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var anchorX: Double?
    var anchorY: Double?
    var opacity: Double
    var rotation: Double
    var scaleX: Double
    var scaleY: Double
    var skewX: Double?
    var skewY: Double?
    var fit: String?
    var fill: FillStyle?
    var effects: JSONValue?
    var filters: JSONValue?
    var motion: MotionStyle?
    var keyframes: [String: [StylePropertyKeyframe]]?
    var animations: [StyleAnimation]?
    var extra: [String: JSONValue] = [:]

    enum CodingKeys: String, CodingKey, CaseIterable {
        case x, y, width, height, anchorX, anchorY, opacity, rotation, scaleX, scaleY, skewX, skewY, fit, fill, effects, filters, motion, keyframes, animations
    }

    init(
        x: Double,
        y: Double,
        width: Double,
        height: Double,
        anchorX: Double? = nil,
        anchorY: Double? = nil,
        opacity: Double,
        rotation: Double,
        scaleX: Double,
        scaleY: Double,
        skewX: Double? = nil,
        skewY: Double? = nil,
        fit: String? = nil,
        fill: FillStyle?,
        effects: JSONValue? = nil,
        filters: JSONValue? = nil,
        motion: MotionStyle? = nil,
        keyframes: [String: [StylePropertyKeyframe]]? = nil,
        animations: [StyleAnimation]? = nil,
        extra: [String: JSONValue] = [:]
    ) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.anchorX = anchorX
        self.anchorY = anchorY
        self.opacity = opacity
        self.rotation = rotation
        self.scaleX = scaleX
        self.scaleY = scaleY
        self.skewX = skewX
        self.skewY = skewY
        self.fit = fit
        self.fill = fill
        self.effects = effects
        self.filters = filters
        self.motion = motion
        self.keyframes = keyframes
        self.animations = animations
        self.extra = extra
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decodeIfPresent(Double.self, forKey: .x) ?? 0
        y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0
        width = try container.decodeIfPresent(Double.self, forKey: .width) ?? 1
        height = try container.decodeIfPresent(Double.self, forKey: .height) ?? 1
        anchorX = try container.decodeIfPresent(Double.self, forKey: .anchorX)
        anchorY = try container.decodeIfPresent(Double.self, forKey: .anchorY)
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        scaleX = try container.decodeIfPresent(Double.self, forKey: .scaleX) ?? 1
        scaleY = try container.decodeIfPresent(Double.self, forKey: .scaleY) ?? 1
        skewX = try container.decodeIfPresent(Double.self, forKey: .skewX)
        skewY = try container.decodeIfPresent(Double.self, forKey: .skewY)
        fit = try container.decodeIfPresent(String.self, forKey: .fit)
        fill = try container.decodeIfPresent(FillStyle.self, forKey: .fill)
        effects = try container.decodeIfPresent(JSONValue.self, forKey: .effects)
        filters = try container.decodeIfPresent(JSONValue.self, forKey: .filters)
        motion = try container.decodeIfPresent(MotionStyle.self, forKey: .motion)
        keyframes = try container.decodeIfPresent([String: [StylePropertyKeyframe]].self, forKey: .keyframes)
        animations = try container.decodeIfPresent([StyleAnimation].self, forKey: .animations)
        extra = try decodeUnknownFields(from: decoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)), keyedBy: CodingKeys.self)
    }

    func encode(to encoder: Encoder) throws {
        try encodeUnknownFields(extra, into: encoder, excluding: Set(CodingKeys.allCases.map(\.rawValue)))
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(x, forKey: .x)
        try container.encode(y, forKey: .y)
        try container.encode(width, forKey: .width)
        try container.encode(height, forKey: .height)
        try container.encodeIfPresent(anchorX, forKey: .anchorX)
        try container.encodeIfPresent(anchorY, forKey: .anchorY)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(rotation, forKey: .rotation)
        try container.encode(scaleX, forKey: .scaleX)
        try container.encode(scaleY, forKey: .scaleY)
        try container.encodeIfPresent(skewX, forKey: .skewX)
        try container.encodeIfPresent(skewY, forKey: .skewY)
        try container.encodeIfPresent(fit, forKey: .fit)
        try container.encodeIfPresent(fill, forKey: .fill)
        try container.encodeIfPresent(effects, forKey: .effects)
        try container.encodeIfPresent(filters, forKey: .filters)
        try container.encodeIfPresent(motion, forKey: .motion)
        try container.encodeIfPresent(keyframes, forKey: .keyframes)
        try container.encodeIfPresent(animations, forKey: .animations)
    }

    static var fallback: VisualLayerStyle {
        VisualLayerStyle(x: 0, y: 0, width: 1, height: 1, opacity: 1, rotation: 0, scaleX: 1, scaleY: 1, fill: nil)
    }

    static func background(_ composition: WorkspaceComposition, color: String) -> VisualLayerStyle {
        VisualLayerStyle(
            x: 0,
            y: 0,
            width: Double(composition.width),
            height: Double(composition.height),
            anchorX: 0.5,
            anchorY: 0.5,
            opacity: 1,
            rotation: 0,
            scaleX: 1,
            scaleY: 1,
            fit: "fill",
            fill: FillStyle(enabled: true, color: color, opacity: 1),
            effects: .object([:])
        )
    }

    static func centered(_ composition: WorkspaceComposition, width: Double, height: Double) -> VisualLayerStyle {
        VisualLayerStyle(
            x: (Double(composition.width) - width) / 2,
            y: (Double(composition.height) - height) / 2,
            width: width,
            height: height,
            anchorX: 0.5,
            anchorY: 0.5,
            opacity: 1,
            rotation: 0,
            scaleX: 1,
            scaleY: 1,
            fit: "contain",
            fill: nil,
            effects: .object([:])
        )
    }
}

struct FillStyle: Codable, Hashable {
    var enabled: Bool
    var color: String
    var opacity: Double
}

struct EvaluatedLayer: Hashable, Identifiable {
    var id: String { clip.id }
    let clip: WorkspaceClip
    let asset: WorkspaceAsset?
    let localTime: Double
    let mediaTime: Double
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let anchorX: Double
    let anchorY: Double
    let opacity: Double
    let rotation: Double
    let scaleX: Double
    let scaleY: Double
    let translateX: Double
    let translateY: Double
    let skewX: Double
    let skewY: Double
    let effects: JSONValue?
}

struct FrameDescriptorSnapshot: Hashable {
    let frameIndex: Int
    let fps: Double
    let width: Int
    let height: Int
    let layers: [EvaluatedLayer]
    let backgroundColor: SIMD4<Float>

    var activeClipIDs: [String] {
        layers.map(\.clip.id)
    }

    var timeSeconds: Double {
        Double(frameIndex) / fps
    }
}

extension Color {
    init(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let value = UInt64(clean, radix: 16) ?? 0
        let r = Double((value >> 16) & 0xff) / 255.0
        let g = Double((value >> 8) & 0xff) / 255.0
        let b = Double(value & 0xff) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

func rgbaFloat(_ hex: String) -> SIMD4<Float> {
    let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
    let value = UInt64(clean, radix: 16) ?? 0xffffff
    return SIMD4<Float>(
        Float((value >> 16) & 0xff) / 255.0,
        Float((value >> 8) & 0xff) / 255.0,
        Float(value & 0xff) / 255.0,
        1
    )
}
