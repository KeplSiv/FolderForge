import XCTest
@testable import FolderForge

final class SetupArchiveTests: XCTestCase {
    func testHomePathsMapWithoutChangingSimilarPrefixesOrExternalVolumes() {
        XCTAssertEqual(SetupArchive.mappedPath("/Users/old/Projects/Code",
                                               sourceHome: "/Users/old",
                                               destinationHome: "/Users/new"),
                       "/Users/new/Projects/Code")
        XCTAssertEqual(SetupArchive.mappedPath("/Users/older/Projects",
                                               sourceHome: "/Users/old",
                                               destinationHome: "/Users/new"),
                       "/Users/older/Projects")
        XCTAssertEqual(SetupArchive.mappedPath("/Volumes/Work/Client",
                                               sourceHome: "/Users/old",
                                               destinationHome: "/Users/new"),
                       "/Volumes/Work/Client")
    }

    func testArchiveRoundTripsOriginalArtworkAndAppliedStyle() throws {
        var style = FolderStyle()
        style.overlay.kind = .text
        style.overlay.text = "RD"
        let look = WorkspaceLook(name: "Before", root: URL(fileURLWithPath: "/Users/old/Projects"),
                                 pairs: [(URL(fileURLWithPath: "/Users/old/Projects/Research"), style)])
        let archive = SetupArchive(sourceHome: "/Users/old", presets: [style], themes: [],
                                   themeAssignments: [], looks: [look], ruleSets: [], activeRuleSetID: nil,
                                   watches: [], appliedFolders: [
                                    .init(path: "/Users/old/Projects/Research", style: style,
                                          originalIconData: Data([1, 2, 3]))
                                   ])
        let decoded = try JSONDecoder.forgeDecoder.decode(
            SetupArchive.self, from: JSONEncoder.forgeEncoder.encode(archive))
        XCTAssertEqual(decoded.appliedFolders[0].originalIconData, Data([1, 2, 3]))
        XCTAssertEqual(decoded.appliedFolders[0].style.overlay.text, "RD")
        XCTAssertEqual(decoded.looks?.first?.entries.first?.style?.overlay.text, "RD")
        XCTAssertEqual(decoded.destination(for: decoded.appliedFolders[0],
                                           home: "/Users/new").path,
                       "/Users/new/Projects/Research")
    }

    func testRuleSetAndWatchMigrationKeepsHierarchyButPausesWatch() throws {
        let storage = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage) }
        let store = SmartRuleStore(storageDirectory: storage)
        let sourceStarter = SmartRuleStore.defaultRuleSet
        let sourceChild = SmartRuleSet(name: "Projects", parentRuleSetID: sourceStarter.id,
                                       rules: [SmartStyleRule(kind: .folderName, pattern: "Design",
                                                              presetName: "Design")])
        let ids = store.importSetupRuleSets([sourceStarter, sourceChild])
        XCTAssertEqual(store.ruleSets.count, 2)
        XCTAssertEqual(store.ruleSets.last?.parentRuleSetID, ids[sourceStarter.id])

        let watch = SmartRuleWatch(rootPath: "/Users/old/Projects", ruleSetID: sourceChild.id,
                                   isEnabled: true, reapplyOnChanges: true)
        store.importSetupWatches([watch], ruleSetIDs: ids, sourceHome: "/Users/old",
                                 destinationHome: "/Users/new")
        XCTAssertEqual(store.watches.first?.rootPath, "/Users/new/Projects")
        XCTAssertEqual(store.watches.first?.ruleSetID, ids[sourceChild.id])
        XCTAssertEqual(store.watches.first?.isEnabled, false)
    }
}

final class IconLegibilityTests: XCTestCase {
    func testWarnsAboutLongTinyLowOpacityText() {
        var style = FolderStyle()
        style.overlay.kind = .text
        style.overlay.text = "Research"
        style.overlayScale = 0.22
        style.overlayOpacity = 0.4
        XCTAssertEqual(IconLegibility.warnings(for: style).count, 3)
    }

    func testContrastCheckFlagsSimilarInkAndTint() {
        var style = FolderStyle()
        style.overlay.kind = .symbol
        style.finish = .tinted
        style.overlayColor = RGBA(hex: "#777777")!
        style.tint = RGBA(hex: "#888888")!
        XCTAssertTrue(IconLegibility.warnings(for: style).contains { $0.contains("Ink") })
        style.overlayColor = .white
        style.tint = RGBA(hex: "#111111")!
        XCTAssertFalse(IconLegibility.warnings(for: style).contains { $0.contains("Ink") })
    }
}
