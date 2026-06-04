import Foundation

enum NativeExportQuality: String, CaseIterable, Identifiable, Hashable, Sendable {
    case preview
    case balanced
    case pro
    case max

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preview: return "Preview"
        case .balanced: return "Balanced"
        case .pro: return "Pro"
        case .max: return "Max"
        }
    }

    var bitrateMultiplier: Double {
        switch self {
        case .preview: return 0.55
        case .balanced: return 1.0
        case .pro: return 1.8
        case .max: return 2.6
        }
    }
}

enum NativeExportScale: String, CaseIterable, Identifiable, Hashable, Sendable {
    case half
    case original
    case double

    var id: String { rawValue }

    var title: String {
        switch self {
        case .half: return "50%"
        case .original: return "100%"
        case .double: return "200%"
        }
    }

    var multiplier: Double {
        switch self {
        case .half: return 0.5
        case .original: return 1
        case .double: return 2
        }
    }
}

enum NativeExportBackend: String, CaseIterable, Identifiable, Hashable, Sendable {
    case hardwareRequired

    var id: String { rawValue }

    var title: String {
        "Hardware"
    }

    var description: String {
        "Require Metal GPU rendering and a proven VideoToolbox hardware encoder. Software fallback is blocked."
    }
}

struct NativeExportSettings: Hashable, Sendable {
    var quality: NativeExportQuality
    var scale: NativeExportScale
    var backend: NativeExportBackend = .hardwareRequired

    func outputWidth(for composition: WorkspaceComposition) -> Int {
        max(2, Int((Double(composition.width) * scale.multiplier).rounded()))
    }

    func outputHeight(for composition: WorkspaceComposition) -> Int {
        max(2, Int((Double(composition.height) * scale.multiplier).rounded()))
    }

    func bitrate(width: Int, height: Int, fps: Double) -> Int {
        let base = Double(width * height) * max(1, fps) / 3
        return max(2_000_000, Int(base * quality.bitrateMultiplier))
    }
}
