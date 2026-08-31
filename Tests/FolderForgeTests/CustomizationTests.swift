import AppKit
import XCTest
@testable import FolderForge

final class ImagePlacementTests: XCTestCase {
    func testSVGImportPreservesVectorSourceData() throws {
        let svg = Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="120" height="60">
          <rect width="120" height="60" fill="#ff3366"/>
        </svg>
        """.utf8)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderForge-\(UUID().uuidString).svg")
        try svg.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertTrue(IconImport.canImport(url))
        let embedded = try XCTUnwrap(IconImport.embeddedData(from: url))
        XCTAssertEqual(embedded, svg)

        var style = FolderStyle()
        style.fill.kind = .image
        style.fill.imageData = embedded
        XCTAssertNotNil(IconRenderer.render(style, pixels: 16))
        XCTAssertNotNil(IconRenderer.render(style, pixels: 512))
    }

    func testFitPreservesWideArtworkWhileFillCoversCanvas() throws {
        let image = NSImage(size: NSSize(width: 200, height: 100))
        image.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 200, height: 100).fill()
        image.unlockFocus()

        let fit = try XCTUnwrap(GlyphFactory.rasterizeFitting(image, side: 100))
        let fill = try XCTUnwrap(GlyphFactory.rasterizeFilling(image, side: 100))
        let fitRep = NSBitmapImageRep(cgImage: fit)
        let fillRep = NSBitmapImageRep(cgImage: fill)

        XCTAssertLessThan(try XCTUnwrap(fitRep.colorAt(x: 50, y: 0)).alphaComponent, 0.1)
        XCTAssertGreaterThan(try XCTUnwrap(fitRep.colorAt(x: 50, y: 50)).alphaComponent, 0.9)
        XCTAssertGreaterThan(try XCTUnwrap(fillRep.colorAt(x: 50, y: 0)).alphaComponent, 0.9)
    }

    func testOldImageFillDefaultsToFillWithoutLosingArtwork() throws {
        var style = FolderStyle()
        style.fill.kind = .image
        style.fill.imageData = Data([1, 2, 3])

        let encoded = try JSONEncoder().encode(style)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var fill = try XCTUnwrap(object["fill"] as? [String: Any])
        fill.removeValue(forKey: "imageContentMode")
        object["fill"] = fill

        let decoded = try JSONDecoder().decode(
            FolderStyle.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(decoded.fill.imageData, Data([1, 2, 3]))
        XCTAssertEqual(decoded.fill.imageContentMode, .fill)
        XCTAssertEqual(decoded.fill.iconHueRotation, 0)
        XCTAssertEqual(decoded.fill.iconSaturation, 1)
        XCTAssertEqual(decoded.fill.iconBrightness, 0)
        XCTAssertEqual(decoded.fill.iconContrast, 1)
    }

    func testImportedIconToneRoundTripsAndChangesRendering() throws {
        let image = NSImage(size: NSSize(width: 64, height: 64))
        image.lockFocus()
        NSColor(calibratedRed: 0.8, green: 0.2, blue: 0.1, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 64, height: 64).fill()
        image.unlockFocus()

        var style = FolderStyle()
        style.fill.kind = .icns
        style.fill.fullIconData = try XCTUnwrap(GlyphFactory.pngData(from: image, side: 64))
        let original = try XCTUnwrap(IconRenderer.render(style, pixels: 64))

        style.fill.iconHueRotation = 45
        style.fill.iconSaturation = 1.4
        style.fill.iconBrightness = -0.2
        style.fill.iconContrast = 1.2
        let adjusted = try XCTUnwrap(IconRenderer.render(style, pixels: 64))

        XCTAssertNotEqual(NSBitmapImageRep(cgImage: original).representation(using: .png,
                                                                              properties: [:]),
                          NSBitmapImageRep(cgImage: adjusted).representation(using: .png,
                                                                              properties: [:]))

        let decoded = try JSONDecoder().decode(FolderStyle.self,
                                                from: JSONEncoder().encode(style))
        XCTAssertEqual(decoded.fill.iconHueRotation, 45)
        XCTAssertEqual(decoded.fill.iconSaturation, 1.4)
        XCTAssertEqual(decoded.fill.iconBrightness, -0.2)
        XCTAssertEqual(decoded.fill.iconContrast, 1.2)
    }
}

final class TextFontTests: XCTestCase {
    func testSelectedTextFontRoundTripsInStyleFiles() throws {
        var style = FolderStyle()
        style.overlay.kind = .text
        style.textFontName = "Helvetica"

        let decoded = try JSONDecoder().decode(
            FolderStyle.self,
            from: JSONEncoder().encode(style)
        )
        XCTAssertEqual(decoded.textFontName, "Helvetica")
    }

    func testSelectedWeightChoosesTheMatchingCustomFontFace() {
        let regular = FontCatalog.font(familyName: "Helvetica", size: 32, weight: .regular)
        let bold = FontCatalog.font(familyName: "Helvetica", size: 32, weight: .bold)
        let manager = NSFontManager.shared

        XCTAssertEqual(regular.familyName, bold.familyName)
        XCTAssertGreaterThan(manager.weight(of: bold), manager.weight(of: regular))
        XCTAssertNotEqual(regular.fontName, bold.fontName)
    }

    func testMissingCustomFontFallsBackToWeightedSystemFont() {
        let font = FontCatalog.font(
            familyName: "FolderForge Definitely Missing Font",
            size: 24,
            weight: .bold
        )

        XCTAssertGreaterThanOrEqual(NSFontManager.shared.weight(of: font), 9)
    }
}

final class AddFoldersSheetLayoutTests: XCTestCase {
    func testShortDisplayUsesCompactScrollableSheetHeight() {
        XCTAssertEqual(AddFoldersSheet.preferredHeight(forVisibleScreenHeight: 800), 624)
    }

    func testLargeDisplayKeepsComfortableMaximumHeight() {
        XCTAssertEqual(AddFoldersSheet.preferredHeight(forVisibleScreenHeight: 1_200), 780)
    }
}

final class LanguagePreferenceTests: XCTestCase {
    func testFirstRunChoicePersistsForLaterLaunches() {
        let suite = "FolderForgeLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let firstLaunch = AppState(engagementDefaults: defaults)
        XCTAssertTrue(firstLaunch.showingLanguageChooser)
        XCTAssertEqual(firstLaunch.appLanguage, .english)
        firstLaunch.appLanguage = .spanish
        firstLaunch.confirmLanguageSelection()

        let laterLaunch = AppState(engagementDefaults: defaults)
        XCTAssertFalse(laterLaunch.showingLanguageChooser)
        XCTAssertEqual(laterLaunch.appLanguage, .spanish)
    }

    func testLegacySystemLanguageMigratesToEnglish() {
        let suite = "FolderForgeLanguageTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("system", forKey: LanguagePreference.languageKey)

        XCTAssertEqual(AppState(engagementDefaults: defaults).appLanguage, .english)
    }
}
