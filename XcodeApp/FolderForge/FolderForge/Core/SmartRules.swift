import CoreServices
import Foundation
import SwiftUI

// MARK: - Rules

enum FolderNameMatch: String, Codable, CaseIterable, Identifiable {
    case exact
    case contains
    case startsWith
    case endsWith
    case glob

    var id: String { rawValue }

    var title: String {
        switch self {
        case .exact: "Exact"
        case .contains: "Contains"
        case .startsWith: "Starts with"
        case .endsWith: "Ends with"
        case .glob: "Glob"
        }
    }
}

enum SmartRuleKind: String, Codable, CaseIterable, Identifiable {
    case folderName
    case relativePath
    case markerFile
    case fileTypeMajority

    var id: String { rawValue }

    var title: String {
        switch self {
        case .folderName: "Folder name"
        case .relativePath: "Relative path"
        case .markerFile: "Marker file"
        case .fileTypeMajority: "File type majority"
        }
    }

    var defaultPriority: Int {
        switch self {
        case .folderName: 400
        case .relativePath: 450
        case .markerFile: 300
        case .fileTypeMajority: 200
        }
    }
}

enum SmartRuleStyleSource: String, Codable, CaseIterable, Identifiable {
    case builtIn
    case custom

    var id: String { rawValue }
    var title: String { self == .builtIn ? "Built-in" : "My Styles" }
}

/// A rule is intentionally plain data: local, inspectable, exportable, and deterministic.
/// `pattern` is used by name, path and marker rules; file rules use `fileExtensions`.
struct SmartStyleRule: Codable, Hashable, Identifiable {
    var id = UUID()
    var kind: SmartRuleKind
    var pattern: String
    var match: FolderNameMatch
    var fileExtensions: [String]
    var threshold: Double
    var presetName: String
    /// `nil` is intentionally treated as built-in so rule files created before custom-style
    /// support remain valid. Keeping the source alongside the name prevents a custom style
    /// called “Code” from accidentally resolving to the built-in Code preset.
    var styleSource: SmartRuleStyleSource? = nil
    var priority: Int
    var exclusionPatterns: [String]
    var isEnabled: Bool
    /// Preserved in exported rule files for backwards compatibility. Rule order is now the
    /// user-facing precedence model, so this value is no longer used to choose a match.
    var isBuiltIn: Bool

    init(kind: SmartRuleKind = .folderName,
         pattern: String = "",
         match: FolderNameMatch = .exact,
         fileExtensions: [String] = [],
         threshold: Double = 0.60,
         presetName: String = "Documents",
         styleSource: SmartRuleStyleSource? = nil,
         priority: Int? = nil,
         exclusionPatterns: [String] = [],
         isEnabled: Bool = true,
         isBuiltIn: Bool = false) {
        self.kind = kind
        self.pattern = pattern
        self.match = match
        self.fileExtensions = fileExtensions
        self.threshold = threshold
        self.presetName = presetName
        self.styleSource = styleSource
        self.priority = priority ?? kind.defaultPriority
        self.exclusionPatterns = exclusionPatterns
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
    }

    func matches(folderName: String, relativePath: String, facts: FolderFacts) -> Bool {
        guard isEnabled, !isExcluded(relativePath: relativePath) else { return false }

        switch kind {
        case .folderName:
            return matches(pattern: pattern, subject: folderName)
        case .relativePath:
            return matches(pattern: pattern, subject: relativePath)
        case .markerFile:
            let markers = FolderScanner.parsePatterns(pattern)
            guard !markers.isEmpty else { return false }
            return facts.markerNames.contains { name in
                markers.contains { FolderScanner.matchesName(name, pattern: $0) }
            }
        case .fileTypeMajority:
            let extensions = Set(fileExtensions.map(Self.normalizedExtension).filter { !$0.isEmpty })
            guard !extensions.isEmpty, facts.fileCount > 0 else { return false }
            let matching = facts.extensions.reduce(0) { partial, entry in
                partial + (extensions.contains(entry.key) ? entry.value : 0)
            }
            return Double(matching) / Double(facts.fileCount) >= threshold
        }
    }

    func explanation(relativePath: String, facts: FolderFacts) -> String {
        let quoted = "\u{201c}\(pattern)\u{201d}"
        switch kind {
        case .folderName:
            return nameExplanation(quoted)
        case .relativePath:
            return "Path \(pathVerb) \(quoted)"
        case .markerFile:
            let markers = FolderScanner.parsePatterns(pattern)
            return markers.count == 1
                ? "Found \(quoted)"
                : "Found one of \(markers.count) project markers"
        case .fileTypeMajority:
            let matching = facts.extensions.reduce(0) { partial, entry in
                partial + (fileExtensions.map(Self.normalizedExtension).contains(entry.key) ? entry.value : 0)
            }
            let percentage = Int((Double(matching) / Double(max(1, facts.fileCount)) * 100).rounded())
            return "\(percentage)% \(fileExtensions.joined(separator: ", ")) files"
        }
    }

    var resolvedStyleSource: SmartRuleStyleSource { styleSource ?? .builtIn }

    private func nameExplanation(_ quoted: String) -> String {
        switch match {
        case .exact: "Name equals \(quoted)"
        case .contains: "Name contains \(quoted)"
        case .startsWith: "Name starts with \(quoted)"
        case .endsWith: "Name ends with \(quoted)"
        case .glob: "Name matches \(quoted)"
        }
    }

    private var pathVerb: String {
        switch match {
        case .exact: "equals"
        case .contains: "contains"
        case .startsWith: "starts with"
        case .endsWith: "ends with"
        case .glob: "matches"
        }
    }

    private func matches(pattern raw: String, subject: String) -> Bool {
        let pattern = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else { return false }
        switch match {
        case .exact:
            return subject.compare(pattern, options: .caseInsensitive) == .orderedSame
        case .contains:
            return subject.range(of: pattern, options: .caseInsensitive) != nil
        case .startsWith:
            return subject.range(of: pattern, options: [.caseInsensitive, .anchored]) != nil
        case .endsWith:
            return subject.range(of: pattern, options: [.caseInsensitive, .anchored, .backwards]) != nil
        case .glob:
            return kind == .relativePath
                ? FolderScanner.matchesPath(subject, pattern: pattern)
                : FolderScanner.matchesName(subject, pattern: pattern)
        }
    }

    private func isExcluded(relativePath: String) -> Bool {
        exclusionPatterns.contains { pattern in
            let cleaned = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty else { return false }
            if FolderScanner.matchesPath(relativePath, pattern: cleaned) { return true }

            // A path picked in the folder chooser is stored as its plain relative path.
            // Treat it as a subtree exclusion, so choosing `Archive` also skips
            // `Archive/2026` without making the user learn glob syntax.
            let hasWildcard = cleaned.contains { "*?[".contains($0) }
            return !hasWildcard && relativePath.hasPrefix(cleaned + "/")
        }
    }

    static func normalizedExtension(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix(".") ? trimmed : ".\(trimmed)"
    }
}

struct SmartRuleSet: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    /// Inherited rules run as a base layer. Rules in this set win ties at the same priority.
    var parentRuleSetID: UUID?
    var rules: [SmartStyleRule]

    init(name: String, parentRuleSetID: UUID? = nil, rules: [SmartStyleRule]) {
        self.name = name
        self.parentRuleSetID = parentRuleSetID
        self.rules = rules
    }
}

struct ResolvedSmartRule: Identifiable {
    let rule: SmartStyleRule
    let sourceRuleSet: String
    let inheritanceDepth: Int
    var id: UUID { rule.id }
}

// MARK: - Inspection and matching

struct FolderFacts: Sendable {
    var markerNames: Set<String> = []
    var extensions: [String: Int] = [:]
    var fileCount = 0
}

enum FolderFactsScanner {
    /// Looks only at a folder's direct children. That makes a 60% image rule predictable and
    /// prevents a giant subtree from turning one small folder into an expensive scan.
    static func scan(url: URL) -> FolderFacts {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isRegularFileKey]
        let children = (try? FileManager.default.contentsOfDirectory(
            // Marker rules intentionally see `.git`; hidden files do not contribute to a
            // file-type majority unless they have a real extension and the user asks for it.
            at: url, includingPropertiesForKeys: Array(keys), options: []
        )) ?? []

        var facts = FolderFacts()
        for child in children {
            let values = try? child.resourceValues(forKeys: keys)
            if values?.isDirectory == true {
                facts.markerNames.insert(child.lastPathComponent)
                continue
            }
            guard values?.isRegularFile == true else { continue }
            facts.fileCount += 1
            let ext = SmartStyleRule.normalizedExtension(child.pathExtension)
            if !ext.isEmpty { facts.extensions[ext, default: 0] += 1 }
            facts.markerNames.insert(child.lastPathComponent)
        }
        return facts
    }
}

struct SmartStyleAlternative: Identifiable {
    let candidate: ResolvedSmartRule
    var id: UUID { candidate.id }
}

struct SmartStyleMatch: Identifiable {
    let url: URL
    let relativePath: String
    let candidate: ResolvedSmartRule
    let style: FolderStyle
    let explanation: String
    let alternatives: [SmartStyleAlternative]

    var id: URL { url }
    var hasConflict: Bool { !alternatives.isEmpty }
}

struct RepeatedFolderName: Identifiable {
    let name: String
    let urls: [URL]
    var id: String { name.localizedLowercase }
}

struct SmartStyleAuditItem: Identifiable {
    let match: SmartStyleMatch
    let currentStyleName: String?
    var id: URL { match.url }
}

struct SmartStylePreview {
    let root: URL
    let scannedURLs: [URL]
    let matches: [SmartStyleMatch]
    let unmatched: [URL]
    let missingPresetRules: [ResolvedSmartRule]
    let repeatedNames: [RepeatedFolderName]
    let auditItems: [SmartStyleAuditItem]
    let truncated: Bool
    /// Deepest eligible folder actually discovered below the root. Used to make a large
    /// requested scan depth understandable instead of silently treating it as an error.
    let deepestLevel: Int

    var conflictCount: Int { matches.filter(\.hasConflict).count }
}

enum SmartStyleEngine {
    static func preview(root: URL, options: FolderScanner.Options,
                        rules: [ResolvedSmartRule], presets: [FolderStyle],
                        customPresets: [FolderStyle] = []) -> SmartStylePreview {
        let scan = FolderScanner.scan(root: root, options: options)
        let builtInByName = Dictionary(presets.map { ($0.name.localizedLowercase, $0) },
                                       uniquingKeysWith: { first, _ in first })
        let customByName = Dictionary(customPresets.map { ($0.name.localizedLowercase, $0) },
                                      uniquingKeysWith: { first, _ in first })
        let needsFacts = rules.contains { $0.rule.kind == .markerFile || $0.rule.kind == .fileTypeMajority }
        var matches: [SmartStyleMatch] = []
        var unmatched: [URL] = []
        var missingPresetRules: [ResolvedSmartRule] = []

        for url in scan.folders {
            let relativePath = relativePath(of: url, root: root)
            let facts = needsFacts ? FolderFactsScanner.scan(url: url) : FolderFacts()
            let candidates = rules.filter {
                $0.rule.matches(folderName: url.lastPathComponent, relativePath: relativePath, facts: facts)
            }
            .sorted(by: isPreferred)

            guard let winner = candidates.first else {
                unmatched.append(url)
                continue
            }
            let catalog = winner.rule.resolvedStyleSource == .custom ? customByName : builtInByName
            guard let style = catalog[winner.rule.presetName.localizedLowercase] else {
                missingPresetRules.append(winner)
                unmatched.append(url)
                continue
            }

            let alternatives = candidates.dropFirst().map { SmartStyleAlternative(candidate: $0) }
            matches.append(SmartStyleMatch(
                url: url,
                relativePath: relativePath,
                candidate: winner,
                style: style,
                explanation: winner.rule.explanation(relativePath: relativePath, facts: facts),
                alternatives: alternatives
            ))
        }

        let distinctMissing = Dictionary(grouping: missingPresetRules, by: { $0.rule.id })
            .compactMap { $0.value.first }
        let repeated = repeatedNames(in: scan.folders)
        let audit = matches.compactMap { match -> SmartStyleAuditItem? in
            let existing = BackupStore.appliedStyle(for: match.url)
            guard existing?.matchesAppearance(of: match.style) != true else { return nil }
            return SmartStyleAuditItem(match: match, currentStyleName: existing?.name)
        }

        return SmartStylePreview(root: root, scannedURLs: scan.folders, matches: matches,
                                 unmatched: unmatched, missingPresetRules: distinctMissing,
                                 repeatedNames: repeated, auditItems: audit,
                                 truncated: scan.truncated, deepestLevel: scan.deepestLevel)
    }

    private static func isPreferred(_ left: ResolvedSmartRule, _ right: ResolvedSmartRule) -> Bool {
        // A rule in the chosen set overrides the inherited base. Within either set, Swift's
        // stable sort preserves the visible row order: first matching rule wins.
        if left.inheritanceDepth != right.inheritanceDepth {
            return left.inheritanceDepth > right.inheritanceDepth
        }
        return false
    }

    private static func relativePath(of url: URL, root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        return String(path.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func repeatedNames(in urls: [URL]) -> [RepeatedFolderName] {
        Dictionary(grouping: urls, by: { $0.lastPathComponent.localizedLowercase })
            .compactMap { key, urls in
                guard urls.count >= 3 else { return nil }
                return RepeatedFolderName(name: urls[0].lastPathComponent,
                                          urls: urls.sorted { $0.path < $1.path })
            }
            .sorted { $0.urls.count > $1.urls.count }
    }
}

// MARK: - Saved rule sets

@Observable
final class SmartRuleStore {
    private(set) var ruleSets: [SmartRuleSet] = []
    private(set) var watches: [SmartRuleWatch] = []
    var activeRuleSetID: UUID
    private var watchService: FolderWatchService?
    private var watchHandler: ((SmartRuleWatch) -> Void)?

    private var rulesURL: URL {
        BackupStore.supportDirectory.appendingPathComponent("smart-rules.json")
    }
    private var watchesURL: URL {
        BackupStore.supportDirectory.appendingPathComponent("smart-rule-watches.json")
    }

    init() {
        let fallback = Self.defaultRuleSet
        activeRuleSetID = fallback.id
        if let data = try? Data(contentsOf: rulesURL),
           let decoded = try? JSONDecoder.forgeDecoder.decode([SmartRuleSet].self, from: data),
           !decoded.isEmpty {
            ruleSets = decoded
            activeRuleSetID = decoded[0].id
            let migrated = Self.migrateLegacyProjectMarkers(in: &ruleSets)
            if Self.attachStarterBase(to: &ruleSets) || migrated { saveRules() }
        } else {
            ruleSets = [fallback]
            saveRules()
        }
        if let data = try? Data(contentsOf: watchesURL),
           let decoded = try? JSONDecoder.forgeDecoder.decode([SmartRuleWatch].self, from: data) {
            watches = decoded
        }
    }

    var activeRuleSet: SmartRuleSet {
        ruleSets.first(where: { $0.id == activeRuleSetID }) ?? ruleSets[0]
    }

    private var starterRuleSetID: UUID? {
        ruleSets.first(where: { $0.rules.contains(where: \.isBuiltIn) })?.id
    }

    var activeIsStarterRuleSet: Bool { activeRuleSetID == starterRuleSetID }
    var starterRuleCount: Int {
        guard let starterRuleSetID,
              let starter = ruleSets.first(where: { $0.id == starterRuleSetID }) else { return 0 }
        return starter.rules.count
    }
    var activeUsesStarterRules: Bool {
        guard let starterRuleSetID else { return false }
        if activeRuleSetID == starterRuleSetID { return true }
        var visited: Set<UUID> = []
        var current = activeRuleSet
        while visited.insert(current.id).inserted {
            if current.parentRuleSetID == starterRuleSetID { return true }
            guard let parentID = current.parentRuleSetID,
                  let parent = ruleSets.first(where: { $0.id == parentID }) else { break }
            current = parent
        }
        return false
    }

    func resolvedRules(for ruleSetID: UUID? = nil) -> [ResolvedSmartRule] {
        let start = ruleSetID ?? activeRuleSetID
        var chain: [SmartRuleSet] = []
        var visited: Set<UUID> = []
        var current = ruleSets.first(where: { $0.id == start })
        while let set = current, visited.insert(set.id).inserted {
            chain.append(set)
            current = set.parentRuleSetID.flatMap { parent in ruleSets.first(where: { $0.id == parent }) }
        }
        return chain.reversed().enumerated().flatMap { depth, set in
            set.rules.map { ResolvedSmartRule(rule: $0, sourceRuleSet: set.name, inheritanceDepth: depth) }
        }
    }

    func createRuleSet(named name: String = "New rule set") {
        let set = SmartRuleSet(name: uniqueName(name), parentRuleSetID: starterRuleSetID, rules: [])
        ruleSets.append(set)
        activeRuleSetID = set.id
        saveRules()
    }

    func duplicateActive() {
        var copy = activeRuleSet
        copy.id = UUID()
        copy.name = uniqueName("\(copy.name) Copy")
        ruleSets.append(copy)
        activeRuleSetID = copy.id
        saveRules()
    }

    func deleteActive() {
        guard ruleSets.count > 1, !activeIsStarterRuleSet else { return }
        ruleSets.removeAll { $0.id == activeRuleSetID }
        for index in ruleSets.indices where ruleSets[index].parentRuleSetID == activeRuleSetID {
            ruleSets[index].parentRuleSetID = nil
        }
        activeRuleSetID = ruleSets[0].id
        saveRules()
    }

    func renameActive(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateActive { $0.name = uniqueName(trimmed, excluding: $0.id) }
    }

    func setActiveParent(_ parentID: UUID?) {
        guard parentID != activeRuleSetID else { return }
        updateActive { $0.parentRuleSetID = parentID }
    }

    func setActiveStarterRulesEnabled(_ enabled: Bool) {
        guard !activeIsStarterRuleSet, let starterRuleSetID else { return }
        updateActive { set in
            if enabled {
                set.parentRuleSetID = starterRuleSetID
            } else if set.parentRuleSetID == starterRuleSetID {
                set.parentRuleSetID = nil
            }
        }
    }

    func addRule() {
        updateActive {
            $0.rules.append(SmartStyleRule(kind: .folderName, pattern: "", match: .exact,
                                            presetName: "Documents"))
        }
    }

    func addPathOverride(relativePath: String, presetName: String,
                         styleSource: SmartRuleStyleSource = .builtIn) {
        updateActive {
            $0.rules.insert(SmartStyleRule(kind: .relativePath, pattern: relativePath,
                                            match: .exact, presetName: presetName,
                                            styleSource: styleSource,
                                            priority: 1000), at: 0)
        }
    }

    func addNameRule(_ name: String, presetName: String,
                     styleSource: SmartRuleStyleSource = .builtIn) {
        updateActive {
            $0.rules.insert(SmartStyleRule(kind: .folderName, pattern: name, match: .exact,
                                            presetName: presetName, styleSource: styleSource,
                                            priority: 500), at: 0)
        }
    }

    func updateRule(_ rule: SmartStyleRule) {
        updateActive { set in
            guard let index = set.rules.firstIndex(where: { $0.id == rule.id }) else { return }
            set.rules[index] = rule
        }
    }

    func deleteRule(_ rule: SmartStyleRule) {
        updateActive { $0.rules.removeAll { $0.id == rule.id } }
    }

    func moveRules(from source: IndexSet, to destination: Int) {
        updateActive { $0.rules.move(fromOffsets: source, toOffset: destination) }
    }

    /// Moves one visible rule immediately before another. The UI uses this for drag and drop,
    /// so the number column remains the only ordering affordance users need to understand.
    func moveRule(_ sourceID: UUID, before destinationID: UUID) {
        guard sourceID != destinationID else { return }
        updateActive { set in
            guard let sourceIndex = set.rules.firstIndex(where: { $0.id == sourceID }) else { return }
            let source = set.rules.remove(at: sourceIndex)
            guard let destinationIndex = set.rules.firstIndex(where: { $0.id == destinationID }) else {
                set.rules.append(source)
                return
            }
            set.rules.insert(source, at: destinationIndex)
        }
    }

    // MARK: Import and export

    static let fileExtension = "folderrules"

    func exportActiveData() -> Data? {
        // Include the complete inheritance chain so a child rule set behaves the same after
        // import on another Mac. Parent-first ordering also makes the exported JSON readable.
        let start = activeRuleSetID
        var chain: [SmartRuleSet] = []
        var visited: Set<UUID> = []
        var current = ruleSets.first(where: { $0.id == start })
        while let set = current, visited.insert(set.id).inserted {
            chain.append(set)
            current = set.parentRuleSetID.flatMap { parent in ruleSets.first(where: { $0.id == parent }) }
        }
        return try? JSONEncoder.forgeEncoder.encode(chain.reversed())
    }

    @discardableResult
    func importRuleSets(from url: URL) -> Int {
        guard let data = try? Data(contentsOf: url) else { return 0 }
        let imported: [SmartRuleSet]
        if let many = try? JSONDecoder.forgeDecoder.decode([SmartRuleSet].self, from: data) {
            imported = many
        } else if let one = try? JSONDecoder.forgeDecoder.decode(SmartRuleSet.self, from: data) {
            imported = [one]
        } else {
            return 0
        }
        let newIDs = Dictionary(uniqueKeysWithValues: imported.map { ($0.id, UUID()) })
        for var set in imported {
            let oldID = set.id
            set.id = newIDs[oldID] ?? UUID()
            set.name = uniqueName(set.name)
            set.parentRuleSetID = set.parentRuleSetID.flatMap { newIDs[$0] }
            ruleSets.append(set)
            activeRuleSetID = set.id
        }
        saveRules()
        return imported.count
    }

    // MARK: Watches

    func watch(for root: URL) -> SmartRuleWatch? {
        watches.first { $0.rootURL == root.standardizedFileURL }
    }

    func setWatch(root: URL, enabled: Bool, scanDepth: Int, includeRoot: Bool,
                  reapplyOnChanges: Bool = true) {
        let root = root.standardizedFileURL
        if let index = watches.firstIndex(where: { $0.rootURL == root }) {
            watches[index].isEnabled = enabled
            watches[index].ruleSetID = activeRuleSetID
            watches[index].scanDepth = scanDepth
            watches[index].includeRoot = includeRoot
            watches[index].reapplyOnChanges = reapplyOnChanges
        } else {
            watches.append(SmartRuleWatch(rootPath: root.path, ruleSetID: activeRuleSetID,
                                          isEnabled: enabled, scanDepth: scanDepth,
                                          includeRoot: includeRoot,
                                          reapplyOnChanges: reapplyOnChanges))
        }
        saveWatches()
        restartWatches()
    }

    func removeWatch(root: URL) {
        watches.removeAll { $0.rootURL == root.standardizedFileURL }
        saveWatches()
        restartWatches()
    }

    func resumeWatches(onChange: @escaping (SmartRuleWatch) -> Void) {
        watchHandler = onChange
        restartWatches()
    }

    private func restartWatches() {
        watchService?.stop()
        guard let watchHandler else { return }
        let enabled = watches.filter(\.isEnabled)
        guard !enabled.isEmpty else { return }
        let service = FolderWatchService(watches: enabled, onChange: watchHandler)
        watchService = service
        service.start()
    }

    private func updateActive(_ change: (inout SmartRuleSet) -> Void) {
        guard let index = ruleSets.firstIndex(where: { $0.id == activeRuleSetID }) else { return }
        change(&ruleSets[index])
        saveRules()
    }

    private func uniqueName(_ base: String, excluding id: UUID? = nil) -> String {
        let trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = trimmed.isEmpty ? "Untitled rules" : trimmed
        let taken = Set(ruleSets.filter { $0.id != id }.map { $0.name.localizedLowercase })
        guard taken.contains(root.localizedLowercase) else { return root }
        var number = 2
        while taken.contains("\(root) \(number)".localizedLowercase) { number += 1 }
        return "\(root) \(number)"
    }

    private func saveRules() {
        guard let data = try? JSONEncoder.forgeEncoder.encode(ruleSets) else { return }
        try? data.write(to: rulesURL, options: .atomic)
    }

    private func saveWatches() {
        guard let data = try? JSONEncoder.forgeEncoder.encode(watches) else { return }
        try? data.write(to: watchesURL, options: .atomic)
    }

    private static let projectMarkerPatterns = [
        "package.json", "Package.swift", "Cargo.toml", "go.mod", "pyproject.toml",
        "requirements.txt", "*.xcodeproj", "CMakeLists.txt", ".git",
    ]

    private static var projectMarkerPattern: String {
        projectMarkerPatterns.joined(separator: ", ")
    }

    /// Smart Style has not shipped yet, but local builds already have the verbose initial
    /// default saved. Collapse only the exact built-in marker group and leave custom rules
    /// untouched so the first update immediately improves the editor.
    private static func migrateLegacyProjectMarkers(in sets: inout [SmartRuleSet]) -> Bool {
        var didMigrate = false
        let legacy = Set(projectMarkerPatterns.map { $0.localizedLowercase })

        for index in sets.indices {
            guard sets[index].name == "Everyday folders" else { continue }
            let markerEntries = sets[index].rules.enumerated().filter { _, rule in
                rule.isBuiltIn && rule.kind == .markerFile && rule.presetName == "Code"
            }
            let found = Set(markerEntries.map { $0.element.pattern.localizedLowercase })
            guard markerEntries.count == projectMarkerPatterns.count, found == legacy,
                  let insertionIndex = markerEntries.map(\.offset).min() else { continue }

            sets[index].rules.removeAll { rule in
                rule.isBuiltIn && rule.kind == .markerFile && legacy.contains(rule.pattern.localizedLowercase)
            }
            sets[index].rules.insert(
                SmartStyleRule(kind: .markerFile, pattern: projectMarkerPattern, match: .glob,
                               presetName: "Code", priority: 300, isBuiltIn: true),
                at: insertionIndex
            )
            didMigrate = true
        }
        return didMigrate
    }

    /// The starter set is the app's small, useful default. New and legacy local rule sets
    /// inherit it until the user explicitly turns the toggle off.
    private static func attachStarterBase(to sets: inout [SmartRuleSet]) -> Bool {
        guard let starterID = sets.first(where: { $0.rules.contains(where: \.isBuiltIn) })?.id else { return false }
        var changed = false
        for index in sets.indices where sets[index].id != starterID && sets[index].parentRuleSetID == nil {
            sets[index].parentRuleSetID = starterID
            changed = true
        }
        return changed
    }

    static let defaultRuleSet = SmartRuleSet(name: "Everyday folders", rules: [
        SmartStyleRule(kind: .markerFile, pattern: projectMarkerPattern, match: .glob,
                       presetName: "Code", priority: 300, isBuiltIn: true),

        SmartStyleRule(kind: .fileTypeMajority, fileExtensions: ["mp3", "flac", "wav", "m4a"],
                       threshold: 0.60, presetName: "Music", priority: 200, isBuiltIn: true),
        SmartStyleRule(kind: .fileTypeMajority, fileExtensions: ["jpg", "jpeg", "png", "heic", "raw"],
                       threshold: 0.60, presetName: "Photos", priority: 200, isBuiltIn: true),
        SmartStyleRule(kind: .fileTypeMajority, fileExtensions: ["mov", "mp4", "mkv", "avi"],
                       threshold: 0.60, presetName: "Video", priority: 200, isBuiltIn: true),
        SmartStyleRule(kind: .fileTypeMajority, fileExtensions: ["pdf", "docx", "txt", "pages"],
                       threshold: 0.60, presetName: "Documents", priority: 200, isBuiltIn: true),
        SmartStyleRule(kind: .fileTypeMajority, fileExtensions: ["swift"], threshold: 0.50,
                       presetName: "Code", priority: 200, isBuiltIn: true),
        SmartStyleRule(kind: .fileTypeMajority, fileExtensions: ["py", "ipynb"], threshold: 0.50,
                       presetName: "Code", priority: 200, isBuiltIn: true),

        SmartStyleRule(kind: .folderName, pattern: "receipts", match: .exact,
                       presetName: "Receipts", priority: 100, isBuiltIn: true),
        SmartStyleRule(kind: .folderName, pattern: "invoice", match: .contains,
                       presetName: "Finance", priority: 100, isBuiltIn: true),
        SmartStyleRule(kind: .folderName, pattern: "payroll", match: .exact,
                       presetName: "Payroll", priority: 100, isBuiltIn: true),
        SmartStyleRule(kind: .folderName, pattern: "tax", match: .startsWith,
                       presetName: "Tax", priority: 100, isBuiltIn: true),
        SmartStyleRule(kind: .folderName, pattern: "contracts", match: .exact,
                       presetName: "Legal", priority: 100, isBuiltIn: true),
        SmartStyleRule(kind: .folderName, pattern: "photos", match: .exact,
                       presetName: "Photos", priority: 100, isBuiltIn: true),
        SmartStyleRule(kind: .folderName, pattern: "screenshots", match: .exact,
                       presetName: "Photos", priority: 100, isBuiltIn: true),
        SmartStyleRule(kind: .folderName, pattern: "archive*", match: .glob,
                       presetName: "Archive", priority: 100, isBuiltIn: true),
    ])
}

// MARK: - Opt-in watch roots

struct SmartRuleWatch: Codable, Hashable, Identifiable {
    var id = UUID()
    var rootPath: String
    var ruleSetID: UUID
    var isEnabled: Bool
    var scanDepth: Int
    var includeRoot: Bool
    /// Renames and new folders cause a dry re-evaluation. Unmatched folders are never reset.
    var reapplyOnChanges: Bool

    var rootURL: URL { URL(fileURLWithPath: rootPath).standardizedFileURL }

    init(rootPath: String, ruleSetID: UUID, isEnabled: Bool, scanDepth: Int = 1,
         includeRoot: Bool = false, reapplyOnChanges: Bool) {
        self.rootPath = rootPath
        self.ruleSetID = ruleSetID
        self.isEnabled = isEnabled
        self.scanDepth = scanDepth
        self.includeRoot = includeRoot
        self.reapplyOnChanges = reapplyOnChanges
    }

    enum CodingKeys: String, CodingKey {
        case id, rootPath, ruleSetID, isEnabled, scanDepth, includeRoot, reapplyOnChanges
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        rootPath = try container.decode(String.self, forKey: .rootPath)
        ruleSetID = try container.decode(UUID.self, forKey: .ruleSetID)
        isEnabled = (try? container.decode(Bool.self, forKey: .isEnabled)) ?? true
        scanDepth = (try? container.decode(Int.self, forKey: .scanDepth)) ?? 1
        includeRoot = (try? container.decode(Bool.self, forKey: .includeRoot)) ?? false
        reapplyOnChanges = (try? container.decode(Bool.self, forKey: .reapplyOnChanges)) ?? true
    }
}

/// FSEvents reports changes anywhere below a root. The service only asks the app to evaluate
/// again; it never writes icons itself, keeping policy and file writes in AppState.
final class FolderWatchService {
    private let watches: [SmartRuleWatch]
    private let onChange: (SmartRuleWatch) -> Void
    private var stream: FSEventStreamRef?
    private var pending: Set<UUID> = []
    private var debounceTask: Task<Void, Never>?

    init(watches: [SmartRuleWatch], onChange: @escaping (SmartRuleWatch) -> Void) {
        self.watches = watches
        self.onChange = onChange
    }

    func start() {
        guard stream == nil else { return }
        let paths = watches.map(\.rootPath) as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, eventCount, eventPaths, _, _ in
            guard let info else { return }
            let service = Unmanaged<FolderWatchService>.fromOpaque(info).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] ?? []
            service.receive(paths: Array(paths.prefix(Int(eventCount))))
        }
        stream = FSEventStreamCreate(nil, callback, &context, paths,
                                    FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                    0.8,
                                    FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents))
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        debounceTask?.cancel()
        debounceTask = nil
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    deinit { stop() }

    private func receive(paths: [String]) {
        for path in paths {
            for watch in watches where path.hasPrefix(watch.rootPath) {
                pending.insert(watch.id)
            }
        }
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.0))
            guard !Task.isCancelled, let self else { return }
            let changed = self.pending
            self.pending.removeAll()
            for watch in self.watches where changed.contains(watch.id) {
                self.onChange(watch)
            }
        }
    }
}
