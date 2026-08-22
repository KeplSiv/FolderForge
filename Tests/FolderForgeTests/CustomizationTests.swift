import AppKit
import XCTest
@testable import FolderForge

final class ImagePlacementTests: XCTestCase {
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
