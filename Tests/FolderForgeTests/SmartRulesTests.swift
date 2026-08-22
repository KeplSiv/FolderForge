import Foundation
import XCTest
@testable import FolderForge

final class SmartRulesTests: XCTestCase {
    private let manager = FileManager.default
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FolderForgeRules-\(UUID().uuidString)")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? manager.removeItem(at: root)
    }

    func testEarlierRuleWinsAndReportsConflict() throws {
        let folder = root.appendingPathComponent("TaxCalculator")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        manager.createFile(atPath: folder.appendingPathComponent("package.json").path, contents: Data())

        let name = SmartStyleRule(kind: .folderName, pattern: "tax", match: .startsWith,
                                  presetName: "Tax", priority: 100)
        let marker = SmartStyleRule(kind: .markerFile, pattern: "package.json", match: .exact,
                                    presetName: "Code", priority: 300)
        let preview = makePreview(rules: [marker, name], presets: [style("Tax"), style("Code")])

        XCTAssertEqual(preview.matches.count, 1)
        XCTAssertEqual(preview.matches[0].style.name, "Code")
        XCTAssertEqual(preview.matches[0].alternatives.count, 1)
    }

    func testGlobAndPathExclusionAreCaseInsensitive() throws {
        let folder = root.appendingPathComponent("CS101 Receipts")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let rule = SmartStyleRule(kind: .folderName, pattern: "cs*receipts", match: .glob,
                                  presetName: "School", priority: 400)
        let excluded = SmartStyleRule(kind: .folderName, pattern: "cs*", match: .glob,
                                      presetName: "School", priority: 500,
                                      exclusionPatterns: ["CS101*"])
        let preview = makePreview(rules: [excluded, rule], presets: [style("School")])

        XCTAssertEqual(preview.matches.first?.style.name, "School")
        XCTAssertEqual(preview.matches.first?.candidate.rule.id, rule.id)
    }

    func testChosenExclusionPathSkipsItsEntireSubtree() throws {
        let archive = root.appendingPathComponent("Archive")
        try manager.createDirectory(at: archive.appendingPathComponent("2026"), withIntermediateDirectories: true)
        let rule = SmartStyleRule(kind: .folderName, pattern: "*", match: .glob,
                                  presetName: "Archive", exclusionPatterns: ["Archive"])

        let preview = makePreview(rules: [rule], presets: [style("Archive")])

        XCTAssertTrue(preview.matches.isEmpty)
        XCTAssertEqual(preview.unmatched.count, 2)
    }

    func testPreviewReportsTheDeepestLevelActuallyFound() throws {
        let child = root.appendingPathComponent("One")
        try manager.createDirectory(at: child.appendingPathComponent("Two/Three"), withIntermediateDirectories: true)

        let preview = makePreview(rules: [], presets: [])

        XCTAssertEqual(preview.deepestLevel, 3)
    }

    func testFileTypeMajorityUsesDirectFiles() throws {
        let folder = root.appendingPathComponent("Vacation")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        for file in ["one.jpg", "two.jpeg", "three.png", "notes.txt"] {
            manager.createFile(atPath: folder.appendingPathComponent(file).path, contents: Data())
        }
        let rule = SmartStyleRule(kind: .fileTypeMajority, fileExtensions: ["jpg", "jpeg", "png"],
                                  threshold: 0.60, presetName: "Photos", priority: 200)
        let preview = makePreview(rules: [rule], presets: [style("Photos")])

        XCTAssertEqual(preview.matches.first?.style.name, "Photos")
        XCTAssertEqual(preview.matches.first?.explanation, "75% jpg, jpeg, png files")
    }

    func testHiddenGitMarkerIsDetected() throws {
        let folder = root.appendingPathComponent("Project")
        try manager.createDirectory(at: folder.appendingPathComponent(".git"), withIntermediateDirectories: true)
        let rule = SmartStyleRule(kind: .markerFile, pattern: ".git", match: .exact,
                                  presetName: "Code", priority: 300)
        let preview = makePreview(rules: [rule], presets: [style("Code")])

        XCTAssertEqual(preview.matches.first?.style.name, "Code")
    }

    func testMarkerRuleAcceptsSeveralProjectMarkersInOneRow() throws {
        let folder = root.appendingPathComponent("Project")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        manager.createFile(atPath: folder.appendingPathComponent("Package.swift").path, contents: Data())
        let rule = SmartStyleRule(kind: .markerFile,
                                  pattern: "package.json, Package.swift, Cargo.toml",
                                  presetName: "Code")

        let preview = makePreview(rules: [rule], presets: [style("Code")])

        XCTAssertEqual(preview.matches.first?.style.name, "Code")
    }

    func testCustomStyleSourceDoesNotCollideWithBuiltInName() throws {
        let folder = root.appendingPathComponent("Projects")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let rule = SmartStyleRule(kind: .folderName, pattern: "projects", match: .exact,
                                  presetName: "Code", styleSource: .custom)
        let builtIn = style("Code")
        var custom = style("Code")
        custom.id = UUID()

        let preview = SmartStyleEngine.preview(
            root: root, options: scanOptions(),
            rules: [ResolvedSmartRule(rule: rule, sourceRuleSet: "Rules", inheritanceDepth: 0)],
            presets: [builtIn], customPresets: [custom]
        )

        XCTAssertEqual(preview.matches.first?.style.id, custom.id)
    }

    func testChildRuleSetWinsOverInheritedRule() throws {
        let folder = root.appendingPathComponent("Assets")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        let parent = SmartStyleRule(kind: .folderName, pattern: "assets", match: .exact,
                                    presetName: "Documents", priority: 400)
        let child = SmartStyleRule(kind: .folderName, pattern: "assets", match: .exact,
                                   presetName: "Design", priority: 400)
        let preview = SmartStyleEngine.preview(
            root: root, options: scanOptions(),
            rules: [ResolvedSmartRule(rule: parent, sourceRuleSet: "Base", inheritanceDepth: 0),
                    ResolvedSmartRule(rule: child, sourceRuleSet: "Child", inheritanceDepth: 1)],
            presets: [style("Documents"), style("Design")]
        )

        XCTAssertEqual(preview.matches.first?.style.name, "Design")
    }

    private func makePreview(rules: [SmartStyleRule], presets: [FolderStyle]) -> SmartStylePreview {
        SmartStyleEngine.preview(
            root: root, options: scanOptions(),
            rules: rules.map { ResolvedSmartRule(rule: $0, sourceRuleSet: "Rules", inheritanceDepth: 0) },
            presets: presets
        )
    }

    private func scanOptions() -> FolderScanner.Options {
        var options = FolderScanner.Options()
        options.depth = Int.max
        options.includeRoot = false
        return options
    }

    private func style(_ name: String) -> FolderStyle {
        var style = FolderStyle()
        style.name = name
        return style
    }
}

final class EngagementTrackerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUp() {
        suiteName = "FolderForgeTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testPromptAppearsAfterFirstSuccessfulApplication() {
        let tracker = EngagementTracker(defaults: defaults)
        XCTAssertTrue(tracker.recordSuccessfulStyleApplication())
        XCTAssertTrue(tracker.shouldShowGitHubStarPrompt())
    }

    func testSnoozeSuppressesPromptForSevenDays() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var tracker = EngagementTracker(defaults: defaults, now: { start })
        XCTAssertTrue(tracker.recordSuccessfulStyleApplication())
        tracker.snoozePrompt()
        XCTAssertFalse(tracker.shouldShowGitHubStarPrompt())

        tracker.now = { start.addingTimeInterval(8 * 24 * 60 * 60) }
        XCTAssertTrue(tracker.shouldShowGitHubStarPrompt())
    }

    func testCompletedPromptNeverReturns() {
        let tracker = EngagementTracker(defaults: defaults)
        XCTAssertTrue(tracker.recordSuccessfulStyleApplication())
        tracker.completePrompt()
        XCTAssertFalse(tracker.shouldShowGitHubStarPrompt())
    }
}

final class FolderStyleLayerTests: XCTestCase {
    func testGranularLayerEditingIsOffByDefault() {
        let style = FolderStyle()

        XCTAssertFalse(style.separateLayerColors)
        XCTAssertTrue(style.backLayer.enabled)
        XCTAssertTrue(style.paperLayer.enabled)
        XCTAssertEqual(style.frontLayer.fillKind, .color)
    }

    func testLegacySeparateColorsMigrateIntoLayerFills() throws {
        var legacy = FolderStyle()
        legacy.separateLayerColors = true
        legacy.backFlapTint = RGBA(hex: "#112233")!
        legacy.paperTint = RGBA(hex: "#F0D080")!
        legacy.frontFlapTint = RGBA(hex: "#445566")!

        let encoded = try JSONEncoder().encode(legacy)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "backLayer")
        object.removeValue(forKey: "paperLayer")
        object.removeValue(forKey: "frontLayer")

        let migrated = try JSONDecoder().decode(
            FolderStyle.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(migrated.backLayer.tint, legacy.backFlapTint)
        XCTAssertEqual(migrated.paperLayer.tint, legacy.paperTint)
        XCTAssertEqual(migrated.frontLayer.tint, legacy.frontFlapTint)
    }

    func testOptionalNativeLayersCanBeHiddenButFrontRemainsVisible() throws {
        var style = FolderStyle()
        style.separateLayerColors = true
        let complete = try XCTUnwrap(IconRenderer.render(style, pixels: 128))

        style.paperLayer.enabled = false
        let withoutPaper = try XCTUnwrap(IconRenderer.render(style, pixels: 128))
        XCTAssertNotEqual(pixelData(complete), pixelData(withoutPaper))

        style.frontLayer.enabled = false
        let frontFlagIgnored = try XCTUnwrap(IconRenderer.render(style, pixels: 128))
        XCTAssertEqual(pixelData(withoutPaper), pixelData(frontFlagIgnored))
    }

    private func pixelData(_ image: CGImage) -> Data {
        Data(image.dataProvider?.data as Data? ?? Data())
    }
}

final class ApplicationIconTests: XCTestCase {
    func testApplicationBundleIconCanBeNormalized() throws {
        let app = URL(fileURLWithPath: "/System/Applications/Calculator.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: app.path) else {
            throw XCTSkip("Calculator is not available on this macOS installation")
        }

        let imported = try XCTUnwrap(IconImport.applicationIcon(from: app))
        XCTAssertEqual(imported.name, "Calculator")
        XCTAssertNotNil(NSImage(data: imported.pngData))
    }

    func testApplicationIconOverlayRoundTrips() throws {
        var style = FolderStyle()
        style.overlay.kind = .appIcon
        style.overlay.sourceAppName = "Example"
        style.overlay.imageData = Data([1, 2, 3, 4])
        style.finish = .natural

        let data = try JSONEncoder.forgeEncoder.encode(style)
        let decoded = try JSONDecoder.forgeDecoder.decode(FolderStyle.self, from: data)

        XCTAssertEqual(decoded.overlay.kind, .appIcon)
        XCTAssertEqual(decoded.overlay.sourceAppName, "Example")
        XCTAssertEqual(decoded.overlay.imageData, Data([1, 2, 3, 4]))
        XCTAssertFalse(decoded.overlay.isEmpty)
    }

}

final class FinishRenderingTests: XCTestCase {
    func testEveryFinishChangesEverySupportedOverlayAtFinderSizes() throws {
        for size in [16, 32, 128] {
            for kind in [OverlayKind.symbol, .emoji, .text, .appIcon] {
                var baseStyle = style(for: kind)
                baseStyle.overlay.kind = .none
                let base = try XCTUnwrap(IconRenderer.render(baseStyle, pixels: size))
                let basePixels = pixelData(base)

                var finishes = Set<Data>()
                for finish in OverlayFinish.allCases {
                    var candidate = style(for: kind)
                    candidate.finish = finish
                    // This previously made Stamped disappear completely.
                    candidate.overlayColor = .white
                    let image = try XCTUnwrap(IconRenderer.render(candidate, pixels: size))
                    let pixels = pixelData(image)
                    XCTAssertNotEqual(pixels, basePixels, "\(kind) / \(finish) vanished at \(size)px")
                    finishes.insert(pixels)
                }
                XCTAssertEqual(finishes.count, OverlayFinish.allCases.count,
                               "Some \(kind) finishes rendered identically at \(size)px")
            }
        }
    }

    func testMonochromeArtworkFinishesRetainInternalDetail() throws {
        let detailed = try artworkPNG(split: true)
        let flat = try artworkPNG(split: false)

        for finish in OverlayFinish.allCases where finish != .natural {
            var detailedStyle = style(for: .appIcon)
            detailedStyle.finish = finish
            detailedStyle.overlay.imageData = detailed

            var flatStyle = detailedStyle
            flatStyle.overlay.imageData = flat

            let detailedImage = try XCTUnwrap(IconRenderer.render(detailedStyle, pixels: 128))
            let flatImage = try XCTUnwrap(IconRenderer.render(flatStyle, pixels: 128))
            XCTAssertNotEqual(pixelData(detailedImage), pixelData(flatImage),
                              "\(finish) discarded the app icon's interior artwork")
        }
    }

    private func style(for kind: OverlayKind) -> FolderStyle {
        var style = FolderStyle()
        style.overlay.kind = kind
        style.overlay.symbolName = "star.fill"
        style.overlay.emoji = "🎨"
        style.overlay.text = "AB"
        style.overlay.imageData = try? artworkPNG(split: true)
        style.overlayScale = 0.46
        style.overlayOpacity = 1
        return style
    }

    private func artworkPNG(split: Bool) throws -> Data {
        let side = 128
        let context = try XCTUnwrap(IconRenderer.makeContext(pixels: side))
        let full = CGRect(x: 0, y: 0, width: side, height: side)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(full)
        if split {
            context.setFillColor(NSColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: side / 2, height: side))
        }
        let image = try XCTUnwrap(context.makeImage())
        let rep = NSBitmapImageRep(cgImage: image)
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }

    private func pixelData(_ image: CGImage) -> Data {
        Data(image.dataProvider?.data as Data? ?? Data())
    }
}
