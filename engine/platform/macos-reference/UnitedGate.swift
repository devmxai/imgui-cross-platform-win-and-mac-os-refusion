import Foundation

struct UnitedGateDiagnostic: Hashable {
    enum Severity: String, Hashable {
        case info
        case warning
        case blocked
    }

    let severity: Severity
    let code: String
    let message: String
}

struct UnitedGateCommand: Hashable {
    let kind: String
    let message: String
}

struct ProjectSnapshot {
    let workspaceURL: URL
    let composition: WorkspaceComposition
    let timeline: WorkspaceTimeline
    let manifest: AssetManifest
    let fullSignature: String
    let coreSignature: String
}

struct UnitedGateState {
    let snapshot: ProjectSnapshot
    let diagnostics: [UnitedGateDiagnostic]
    let sceneOnlyChange: Bool

    var composition: WorkspaceComposition { snapshot.composition }
    var timeline: WorkspaceTimeline { snapshot.timeline }
    var assets: [WorkspaceAsset] { snapshot.manifest.assets }
    var fullSignature: String { snapshot.fullSignature }
    var coreSignature: String { snapshot.coreSignature }
}

enum UnitedGateError: LocalizedError {
    case blocked([UnitedGateDiagnostic])

    var errorDescription: String? {
        switch self {
        case .blocked(let diagnostics):
            let messages = diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " ")
            return "UnitedGate blocked project change. \(messages)"
        }
    }
}

struct ProjectContractValidator {
    func validate(_ snapshot: ProjectSnapshot) -> [UnitedGateDiagnostic] {
        var diagnostics: [UnitedGateDiagnostic] = []
        diagnostics.append(contentsOf: validateComposition(snapshot.composition))
        diagnostics.append(contentsOf: validateAssets(snapshot.manifest.assets, workspaceURL: snapshot.workspaceURL))
        diagnostics.append(contentsOf: validateTimeline(snapshot.timeline, assets: snapshot.manifest.assets))
        return diagnostics
    }

    private func validateComposition(_ composition: WorkspaceComposition) -> [UnitedGateDiagnostic] {
        var diagnostics: [UnitedGateDiagnostic] = []
        if composition.width <= 0 || composition.height <= 0 {
            diagnostics.append(.init(severity: .blocked, code: "invalid-composition-size", message: "composition.json width/height must be positive."))
        }
        if !composition.fps.isFinite || composition.fps <= 0 {
            diagnostics.append(.init(severity: .blocked, code: "invalid-fps", message: "composition.json fps must be a positive number."))
        }
        if !composition.durationSeconds.isFinite || composition.durationSeconds <= 0 {
            diagnostics.append(.init(severity: .blocked, code: "invalid-duration", message: "composition.json durationSeconds must be positive."))
        }
        return diagnostics
    }

    private func validateAssets(_ assets: [WorkspaceAsset], workspaceURL: URL) -> [UnitedGateDiagnostic] {
        assets.compactMap { asset in
            let fileURL = workspaceURL.appendingPathComponent(asset.path)
            guard ["video", "image", "audio"].contains(asset.type), !FileManager.default.fileExists(atPath: fileURL.path) else {
                return nil
            }
            return UnitedGateDiagnostic(
                severity: .warning,
                code: "missing-asset-file",
                message: "Asset \(asset.id) points to missing file: \(asset.path)."
            )
        }
    }

    private func validateTimeline(_ timeline: WorkspaceTimeline, assets: [WorkspaceAsset]) -> [UnitedGateDiagnostic] {
        let assetIDs = Set(assets.map(\.id))
        var diagnostics: [UnitedGateDiagnostic] = []
        for track in timeline.tracks {
            for clip in track.clips {
                if !clip.start.isFinite || clip.start < 0 {
                    diagnostics.append(.init(severity: .blocked, code: "invalid-clip-start", message: "Clip \(clip.id) has invalid start time."))
                }
                if !clip.duration.isFinite || clip.duration <= 0 {
                    diagnostics.append(.init(severity: .blocked, code: "invalid-clip-duration", message: "Clip \(clip.id) has invalid duration."))
                }
                if let assetId = clip.assetId, ["video", "image", "audio"].contains(clip.type), !assetIDs.contains(assetId) {
                    diagnostics.append(.init(severity: .warning, code: "missing-asset-id", message: "Clip \(clip.id) references missing assetId \(assetId)."))
                }
                if !(clip.keyframes?.isEmpty ?? true) {
                    diagnostics.append(.init(severity: .warning, code: "legacy-clip-keyframes", message: "Clip \(clip.id) uses legacy clip.keyframes; canonical motion belongs under style.keyframes or style.motion."))
                }
                if clip.extra["effects"] != nil {
                    diagnostics.append(.init(severity: .warning, code: "legacy-clip-effects", message: "Clip \(clip.id) uses clip.effects; canonical effects must be under style.effects."))
                }
                diagnostics.append(contentsOf: validateStyle(clip.style, clipID: clip.id))
            }
        }
        return diagnostics
    }

    private func validateStyle(_ style: VisualLayerStyle, clipID: String) -> [UnitedGateDiagnostic] {
        var diagnostics: [UnitedGateDiagnostic] = []
        let knownButNotYetRenderedStyleFields = ["glow", "colorCorrection"]
        for key in knownButNotYetRenderedStyleFields where style.extra[key] != nil {
            diagnostics.append(.init(severity: .warning, code: "style-field-preserved-not-rendered", message: "Clip \(clipID) contains style.\(key); it is preserved and must enter the RenderGraph before renderer truth."))
        }
        diagnostics.append(contentsOf: FXRegistry.shared.validateEffects(style.effects, clipID: clipID))
        return diagnostics
    }
}

struct UnitedGate {
    private let validator = ProjectContractValidator()

    func openWorkspace(at url: URL, previousFullSignature: String = "", previousCoreSignature: String = "") throws -> UnitedGateState {
        try ensureMinimumWorkspace(at: url)
        return try ingestWorkspace(at: url, previousFullSignature: previousFullSignature, previousCoreSignature: previousCoreSignature)
    }

    func reloadExternalChange(at url: URL, previousFullSignature: String, previousCoreSignature: String) throws -> UnitedGateState {
        try ingestWorkspace(at: url, previousFullSignature: previousFullSignature, previousCoreSignature: previousCoreSignature)
    }

    func writeTimeline(_ timeline: WorkspaceTimeline, to workspaceURL: URL) throws -> UnitedGateState {
        try validatePendingChange(timeline: timeline, manifest: nil, workspaceURL: workspaceURL)
        let data = try JSONEncoder.pretty.encode(timeline)
        try data.write(to: workspaceURL.appendingPathComponent("timeline.json"), options: [.atomic])
        return try ingestWorkspace(at: workspaceURL, previousFullSignature: "", previousCoreSignature: "")
    }

    func writeAssetManifest(_ manifest: AssetManifest, to workspaceURL: URL) throws -> UnitedGateState {
        try validatePendingChange(timeline: nil, manifest: manifest, workspaceURL: workspaceURL)
        let data = try JSONEncoder.pretty.encode(manifest)
        try data.write(to: workspaceURL.appendingPathComponent("assets/assets.json"), options: [.atomic])
        return try ingestWorkspace(at: workspaceURL, previousFullSignature: "", previousCoreSignature: "")
    }

    func fullSignature(at url: URL) -> String {
        workspaceSignature(at: url, paths: [
            "project.json",
            "composition.json",
            "timeline.json",
            "assets/assets.json",
            "assets/originals",
            "native-scenes/main"
        ])
    }

    private func ingestWorkspace(at url: URL, previousFullSignature: String, previousCoreSignature: String) throws -> UnitedGateState {
        let snapshot = try readSnapshot(at: url)
        var diagnostics = validator.validate(snapshot)
        let sceneOnlyChange = !previousFullSignature.isEmpty
            && snapshot.fullSignature != previousFullSignature
            && snapshot.coreSignature == previousCoreSignature
        if sceneOnlyChange {
            diagnostics.append(.init(severity: .warning, code: "web-scene-only-change", message: "native-scenes/main changed without core timeline/assets/composition changes; macOS native visual truth comes from HyperFrame project files."))
        }
        return UnitedGateState(snapshot: snapshot, diagnostics: diagnostics, sceneOnlyChange: sceneOnlyChange)
    }

    private func readSnapshot(at url: URL) throws -> ProjectSnapshot {
        let decoder = JSONDecoder()
        let composition = try decoder.decode(WorkspaceComposition.self, from: Data(contentsOf: url.appendingPathComponent("composition.json")))
        let timeline = try decoder.decode(WorkspaceTimeline.self, from: Data(contentsOf: url.appendingPathComponent("timeline.json")))
        let manifest = try decoder.decode(AssetManifest.self, from: Data(contentsOf: url.appendingPathComponent("assets/assets.json")))
        return ProjectSnapshot(
            workspaceURL: url,
            composition: composition,
            timeline: timeline,
            manifest: manifest,
            fullSignature: fullSignature(at: url),
            coreSignature: workspaceSignature(at: url, paths: ["project.json", "composition.json", "timeline.json", "assets/assets.json"])
        )
    }

    private func validatePendingChange(timeline pendingTimeline: WorkspaceTimeline?, manifest pendingManifest: AssetManifest?, workspaceURL: URL) throws {
        let current = try readSnapshot(at: workspaceURL)
        let snapshot = ProjectSnapshot(
            workspaceURL: workspaceURL,
            composition: current.composition,
            timeline: pendingTimeline ?? current.timeline,
            manifest: pendingManifest ?? current.manifest,
            fullSignature: current.fullSignature,
            coreSignature: current.coreSignature
        )
        let diagnostics = validator.validate(snapshot)
        let blockers = diagnostics.filter { $0.severity == .blocked }
        if !blockers.isEmpty {
            throw UnitedGateError.blocked(blockers)
        }
    }

    private func ensureMinimumWorkspace(at url: URL) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url.appendingPathComponent("assets/originals"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: url.appendingPathComponent("native-scenes/main"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: url.appendingPathComponent("renders"), withIntermediateDirectories: true)
        try ensureFile(url.appendingPathComponent("project.json"), """
        {
          "id": "\(makeId("project"))",
          "name": "\(url.lastPathComponent)",
          "createdAt": "\(Self.isoNow())"
        }
        """)
        try ensureFile(url.appendingPathComponent("composition.json"), """
        {
          "width": 1080,
          "height": 1920,
          "fps": 30,
          "durationSeconds": 13.26
        }
        """)
        try ensureFile(url.appendingPathComponent("assets/assets.json"), """
        {
          "version": 1,
          "updatedAt": "\(Self.isoNow())",
          "assets": []
        }
        """)
        try ensureFile(url.appendingPathComponent("timeline.json"), defaultTimelineJSON())
        try ensureFile(url.appendingPathComponent("native-scenes/main/index.html"), """
        <main class="scene" data-scene="main">
          <canvas class="scene-canvas" data-remake-export width="1080" height="1920"></canvas>
        </main>
        """)
        try ensureFile(url.appendingPathComponent("native-scenes/main/scene.css"), """
        html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: transparent; }
        .scene { width: 1080px; height: 1920px; overflow: hidden; }
        .scene-canvas { display: block; width: 100%; height: 100%; }
        """)
        try ensureFile(url.appendingPathComponent("native-scenes/main/scene.js"), """
        (() => {
          const canvas = document.querySelector('[data-remake-export]');
          const ctx = canvas.getContext('2d');
          const duration = 13.26;
          function seek(time) { ctx.clearRect(0, 0, canvas.width, canvas.height); }
          window.__remake = { duration, seek, playFrom: seek, pause() {}, getExportCanvas: () => canvas };
          seek(0);
        })();
        """)
    }

    private func workspaceSignature(at url: URL, paths: [String]) -> String {
        paths.flatMap { relativePath -> [String] in
            let fileURL = url.appendingPathComponent(relativePath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else { return [] }
            if isDirectory.boolValue {
                return directorySignatureEntries(fileURL, root: url)
            }
            return [signatureEntry(for: fileURL, root: url)]
        }
        .sorted()
        .joined(separator: "|")
    }

    private func directorySignatureEntries(_ directory: URL, root: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return enumerator.compactMap { item in
            guard let fileURL = item as? URL,
                  let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory != true else { return nil }
            return signatureEntry(for: fileURL, root: root)
        }
    }

    private func signatureEntry(for fileURL: URL, root: URL) -> String {
        let relativePath = fileURL.path.replacingOccurrences(of: root.path + "/", with: "")
        guard let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]) else {
            return "\(relativePath):missing"
        }
        return "\(relativePath):\(values.contentModificationDate?.timeIntervalSince1970 ?? 0):\(values.fileSize ?? 0)"
    }

    private func ensureFile(_ url: URL, _ content: String) throws {
        if !FileManager.default.fileExists(atPath: url.path) {
            try content.data(using: .utf8)?.write(to: url, options: .atomic)
        }
    }

    private func defaultTimelineJSON() -> String {
        """
        {
          "version": 1,
          "fps": 30,
          "durationSeconds": 13.26,
          "timebase": {
            "fps": 30,
            "timelineTimeUnit": "seconds",
            "clipStartTimeMode": "absolute-timeline-seconds",
            "clipDurationMode": "seconds",
            "keyframeTimeMode": "clip-local-seconds",
            "animationTimeOrigin": "clip-start"
          },
          "agentContract": {
            "version": 1,
            "summary": "All visible, renderable, selectable, and exportable changes must be represented in timeline.json/assets/assets.json/composition.json and ingested by UnitedGate.",
            "effectPath": "clip.style.effects.<effectName>",
            "sourceOfTruth": ["composition.json", "timeline.json", "assets/assets.json"]
          },
          "updatedAt": "\(Self.isoNow())",
          "tracks": []
        }
        """
    }

    private func makeId(_ prefix: String) -> String {
        "\(prefix)_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12))"
    }

    static func isoNow() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}
