import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Preview-first deterministic automation. The scanner never writes an icon until the user
/// explicitly presses Apply; every row states which rule produced the proposed style.
struct SmartStyleSheet: View {
    @Bindable var state: AppState
    @Environment(\.dismiss) private var dismiss

    /// Used by the off-screen UI snapshot harness; normal launches leave this blank.
    var initialPath = ""

    @State private var pathText = ""
    @State private var includeRoot = false
    /// Start conservatively. A Desktop scan should surface its immediate folders, not dive
    /// into every repository and cache before the user has opted into that cost.
    @State private var scanDepth = 1
    @State private var scansAllLevels = false
    @State private var preview: SmartStylePreview?
    @State private var scanning = false
    @State private var scanTask: Task<Void, Never>?
    @State private var showingRules = false
    @State private var showingRuleSetOptions = false
    @State private var showingRepeatedStructures = false
    @State private var showingAudit = false

    private var resolvedRoot: URL? { FolderScanner.resolve(path: pathText) }
    private var rootExists: Bool {
        guard let root = resolvedRoot else { return false }
        var directory = ObjCBool(false)
        return FileManager.default.fileExists(atPath: root.path, isDirectory: &directory) && directory.boolValue
    }
    private var builtInPresets: [FolderStyle] { state.presets.builtIn }
    private var customPresets: [FolderStyle] { state.presets.userPresets }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    rootSection
                    Divider()
                    ruleSetSection
                    Divider()
                    rulesSection
                    Divider()
                    resultsSection
                    if let root = resolvedRoot, rootExists {
                        Divider()
                        watchSection(root: root)
                    }
                }
                .padding(18)
            }
            Divider()
            footer
        }
        .frame(width: 760, height: 800)
        .onAppear {
            if pathText.isEmpty {
                pathText = initialPath.isEmpty
                    ? state.selectedFolders.first?.url.path
                    ?? FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first?.path
                    ?? NSHomeDirectory()
                    : initialPath
            }
            rescan()
        }
        .onDisappear { scanTask?.cancel() }
        .onChange(of: pathText) { _, _ in rescan() }
        .onChange(of: includeRoot) { _, _ in rescan() }
        .onChange(of: state.smartRules.activeRuleSetID) { _, _ in rescan() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Smart Style").font(.system(size: 15, weight: .semibold))
                Text("Match deterministic local rules across a folder tree before applying.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var rootSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Style this folder tree", symbol: "folder.badge.gearshape")
            HStack(spacing: 7) {
                Image(systemName: "folder")
                    .foregroundStyle(rootExists ? Color.accentColor : .secondary)
                TextField("~/Businesses", text: $pathText)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.plain)
                Button("Browse…") { browse() }.controlSize(.small)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(rootExists ? Color.accentColor.opacity(0.5) : .clear, lineWidth: 1)
            }

            Toggle("Also evaluate the selected root folder", isOn: $includeRoot)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
            HStack(spacing: 8) {
                Text("Look in")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .leading)
                TextField("Depth", value: $scanDepth, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .frame(width: 48)
                    .disabled(scansAllLevels)
                    .onChange(of: scanDepth) { _, value in
                        scanDepth = max(value, 1)
                        rescan()
                    }
                Stepper("", value: $scanDepth, in: 1...Int.max)
                    .labelsHidden()
                    .disabled(scansAllLevels)
                Text(scanDepth == 1 ? "level down" : "levels down")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Toggle("All levels", isOn: $scansAllLevels)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .onChange(of: scansAllLevels) { _, _ in rescan() }
                Spacer()
            }
            Text(scopeDescription)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
    }

    private var effectiveScanDepth: Int {
        scansAllLevels ? Int.max : max(scanDepth, 1)
    }

    private var scopeDescription: String {
        let scope: String
        if scansAllLevels {
            scope = "Scans every nested level"
        } else {
            scope = "Scans \(scanDepth) level\(scanDepth == 1 ? "" : "s") below the root"
        }
        return "\(scope). Hidden folders, bundles, symlinks, and normal safe exclusions stay out. Maximum 2,000 folders per run."
    }

    private var ruleSetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SectionLabel(text: "Rule set", symbol: "slider.horizontal.3")

                Picker("Active rule set", selection: $state.smartRules.activeRuleSetID) {
                    ForEach(state.smartRules.ruleSets) { set in
                        Text(set.name).tag(set.id)
                    }
                }
                .labelsHidden()
                .frame(width: 270, alignment: .leading)
                .fixedSize(horizontal: true, vertical: false)

                Divider().frame(height: 20)

                if state.smartRules.activeIsStarterRuleSet {
                    Label("Starter base", systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                    Text("\(state.smartRules.starterRuleCount) built-in rules")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    Toggle("Use starter rules", isOn: starterRulesBinding)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11, weight: .medium))
                    Text(ruleSetSummary)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Button { state.smartRules.createRuleSet(); rescan() } label: {
                        Image(systemName: "plus")
                    }
                    .help("New rule set")
                    .controlSize(.small)

                    Menu {
                        Button(showingRuleSetOptions ? "Hide name editor" : "Rename rule set") {
                            withAnimation(.easeOut(duration: 0.14)) { showingRuleSetOptions.toggle() }
                        }
                        Button("Duplicate rule set") { state.smartRules.duplicateActive(); rescan() }
                        Divider()
                        Button("Export rule set…") { exportRules() }
                        Button("Import rule set…") { importRules() }
                        Divider()
                        Button("Delete rule set", role: .destructive) {
                            state.smartRules.deleteActive()
                            rescan()
                        }
                        .disabled(state.smartRules.ruleSets.count == 1 || state.smartRules.activeIsStarterRuleSet)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .help("Rule set actions")
                    .controlSize(.small)
                }
            }

            if showingRuleSetOptions {
                HStack(spacing: 8) {
                    Text("Name")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)
                    TextField("Rule set name", text: activeNameBinding)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
                Text(state.smartRules.activeIsStarterRuleSet
                     ? "This is the editable starter base that new rule sets use by default."
                     : "Local rules run before the starter base when both rules match.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var starterRulesBinding: Binding<Bool> {
        Binding(
            get: { state.smartRules.activeUsesStarterRules },
            set: { enabled in
                state.smartRules.setActiveStarterRulesEnabled(enabled)
                rescan()
            }
        )
    }

    private var ruleSetSummary: String {
        let localRuleCount = state.smartRules.activeRuleSet.rules.count
        if state.smartRules.activeIsStarterRuleSet {
            return "\(localRuleCount) shipped starter rules"
        }
        if state.smartRules.activeUsesStarterRules {
            return "\(state.smartRules.starterRuleCount) starter rules + \(localRuleCount) custom"
        }
        return "\(localRuleCount) custom rules"
    }

    private var activeNameBinding: Binding<String> {
        Binding(get: { state.smartRules.activeRuleSet.name }, set: { value in
            state.smartRules.renameActive(to: value)
            rescan()
        })
    }

    private var rulesSection: some View {
        FullWidthDisclosure(isExpanded: $showingRules) {
            HStack {
                SectionLabel(text: rulesSectionTitle, symbol: "point.3.connected.trianglepath.dotted")
                Spacer()
                Text(rulesSectionDetail)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(state.smartRules.activeRuleSet.rules.enumerated()), id: \.element.id) { index, rule in
                    SmartRuleEditorRow(
                        rule: rule,
                        order: index + 1,
                        root: rootExists ? resolvedRoot : nil,
                        builtInPresets: builtInPresets,
                        customPresets: customPresets,
                        onChange: { updated in state.smartRules.updateRule(updated); rescan() },
                        onDelete: { state.smartRules.deleteRule(rule); rescan() },
                        onMoveBefore: { sourceID, destinationID in
                            state.smartRules.moveRule(sourceID, before: destinationID)
                            rescan()
                        }
                    )
                }
                Button { state.smartRules.addRule(); rescan() } label: {
                    Label("Add Rule", systemImage: "plus")
                }
                .controlSize(.small)
            }
            .padding(.top, 8)
        }
    }

    private var rulesSectionTitle: String {
        let count = state.smartRules.activeRuleSet.rules.count
        return state.smartRules.activeIsStarterRuleSet
            ? "Rules (\(count) starter)"
            : "Rules (\(count) custom)"
    }

    private var rulesSectionDetail: String {
        if state.smartRules.activeUsesStarterRules && !state.smartRules.activeIsStarterRuleSet {
            return "\(state.smartRules.starterRuleCount) starter rules active · drag numbers to reorder"
        }
        return "Drag the number to reorder. First matching rule wins"
    }

    @ViewBuilder
    private var resultsSection: some View {
        HStack {
            SectionLabel(text: "Preview", symbol: "checklist")
            Spacer()
            if scanning {
                ProgressView().controlSize(.small)
                Text("Scanning…").font(.system(size: 11)).foregroundStyle(.secondary)
            } else if let preview {
                Text("\(preview.matches.count) matched · \(preview.unmatched.count) unmatched · \(preview.conflictCount) conflicts")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }

        if let preview {
            VStack(alignment: .leading, spacing: 8) {
                if preview.truncated {
                    Label("Stopped at the 2,000-folder safety cap. Narrow the root or exclusions before applying.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
                if !preview.truncated, !scansAllLevels, scanDepth > preview.deepestLevel {
                    Text("Only \(preview.deepestLevel) level\(preview.deepestLevel == 1 ? "" : "s") available below this root.")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
                if !preview.missingPresetRules.isEmpty {
                    Label("\(preview.missingPresetRules.count) rule\(preview.missingPresetRules.count == 1 ? "" : "s") refer to a preset that no longer exists. Those folders are left unchanged.",
                          systemImage: "exclamationmark.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }

                if preview.matches.isEmpty, preview.unmatched.isEmpty {
                    smartStyleEmptyState
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(preview.matches) { match in
                                matchRow(match)
                            }
                            ForEach(preview.unmatched.prefix(80), id: \.self) { url in
                                HStack(spacing: 8) {
                                    Image(systemName: "minus.circle").font(.system(size: 10)).foregroundStyle(.tertiary)
                                    Text(url.lastPathComponent).font(.system(size: 11))
                                    Spacer()
                                    Text("No rule matched").font(.system(size: 10)).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 7).padding(.vertical, 5)
                            }
                            if preview.unmatched.count > 80 {
                                Text("…and \(preview.unmatched.count - 80) more unmatched folders")
                                    .font(.system(size: 10)).foregroundStyle(.tertiary).padding(7)
                            }
                        }
                    }
                    .frame(height: 245)
                    .padding(5)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 7))
                }

                if !preview.repeatedNames.isEmpty {
                    FullWidthDisclosure(isExpanded: $showingRepeatedStructures) {
                        Text("Repeated structures (\(preview.repeatedNames.count))")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    } content: {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(preview.repeatedNames.prefix(8)) { repeated in
                                HStack {
                                    Text("\(repeated.name) · \(repeated.urls.count) places")
                                        .font(.system(size: 11))
                                    Spacer()
                                    Menu("Create Rule") {
                                        Section("Built-in") {
                                            ForEach(builtInPresets) { preset in
                                                Button(preset.name) {
                                                    state.smartRules.addNameRule(repeated.name, presetName: preset.name)
                                                    rescan()
                                                }
                                            }
                                        }
                                        if !customPresets.isEmpty {
                                            Section("My Styles") {
                                                ForEach(customPresets) { preset in
                                                    Button(preset.name) {
                                                        state.smartRules.addNameRule(repeated.name, presetName: preset.name,
                                                                                     styleSource: .custom)
                                                        rescan()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(.top, 5)
                    }
                }

                if !preview.auditItems.isEmpty {
                    FullWidthDisclosure(isExpanded: $showingAudit) {
                        Text("Consistency audit: \(preview.auditItems.count) need attention")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    } content: {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(preview.auditItems.prefix(20)) { item in
                                HStack(spacing: 6) {
                                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                                    Text(item.match.url.lastPathComponent).font(.system(size: 11))
                                    Spacer()
                                    Text(item.currentStyleName ?? "No FolderForge style")
                                        .font(.system(size: 10)).foregroundStyle(.tertiary)
                                    Image(systemName: "arrow.right").font(.system(size: 9)).foregroundStyle(.tertiary)
                                    Text(item.match.style.name).font(.system(size: 10, weight: .medium))
                                }
                            }
                        }
                        .padding(.top, 5)
                    }
                }
            }
        } else if !rootExists, !pathText.isEmpty {
            Label("That folder does not exist.", systemImage: "xmark.circle.fill")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private var smartStyleEmptyState: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "folder.badge.questionmark")
                .font(.system(size: 24))
                .foregroundStyle(Color.accentColor)
                .frame(width: 34)

            VStack(alignment: .leading, spacing: 5) {
                Text("Nothing to preview in this scope")
                    .font(.system(size: 12, weight: .semibold))
                Text("Choose a folder that contains subfolders, increase Look in, or include the selected root folder.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Button("Choose Another Folder…") { browse() }
                        .controlSize(.small)
                    if !includeRoot {
                        Button("Include This Folder") { includeRoot = true }
                            .controlSize(.small)
                    }
                }
                .padding(.top, 3)
            }
            Spacer()
        }
        .padding(14)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 9))
    }

    private func matchRow(_ match: SmartStyleMatch) -> some View {
        HStack(spacing: 8) {
            Image(systemName: match.hasConflict ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(match.hasConflict ? .orange : .green)
            FolderIconView(style: match.style, side: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(match.relativePath).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text("\(match.explanation) → \(match.style.name)")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if match.hasConflict {
                Menu {
                    Text("Priority chose \(match.style.name)")
                    Divider()
                    ForEach(match.alternatives) { alternative in
                        Button("Use \(alternative.candidate.rule.presetName) here") {
                            state.smartRules.addPathOverride(relativePath: match.relativePath,
                                                              presetName: alternative.candidate.rule.presetName,
                                                              styleSource: alternative.candidate.rule.resolvedStyleSource)
                            rescan()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Choose a path-specific override")
            }
        }
        .padding(.horizontal, 7).padding(.vertical, 5)
        .background(match.hasConflict ? Color.orange.opacity(0.08) : .clear,
                    in: RoundedRectangle(cornerRadius: 5))
    }

    private func watchSection(root: URL) -> some View {
        let enabled = state.smartRules.watch(for: root)?.isEnabled ?? false
        return VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "Apply to new folders", symbol: "dot.radiowaves.left.and.right")
            Toggle("Watch this root and reapply unambiguous matches after changes", isOn: Binding(
                get: { enabled },
                set: { value in
                    state.smartRules.setWatch(root: root, enabled: value,
                                              scanDepth: effectiveScanDepth, includeRoot: includeRoot)
                }
            ))
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            Text("Opt-in and local. Uses the selected scope while FolderForge is running; unmatched folders are never reverted or reset.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }

    private var footer: some View {
        HStack {
            if let preview {
                Text("Matched \(preview.matches.count) · Unmatched \(preview.unmatched.count) · Conflicts \(preview.conflictCount)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Apply \(preview?.matches.count ?? 0)") {
                if let preview { state.applySmartStyle(preview) }
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(preview?.matches.isEmpty ?? true)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private func browse() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        if let root = resolvedRoot, rootExists { panel.directoryURL = root }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        pathText = url.path
    }

    private func rescan() {
        scanTask?.cancel()
        guard let root = resolvedRoot, rootExists else {
            preview = nil
            scanning = false
            return
        }
        var options = FolderScanner.Options()
        options.depth = effectiveScanDepth
        options.includeRoot = includeRoot
        let rules = state.smartRules.resolvedRules()
        let presets = builtInPresets
        let custom = customPresets
        scanning = true
        scanTask = Task {
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                SmartStyleEngine.preview(root: root, options: options, rules: rules,
                                         presets: presets, customPresets: custom)
            }.value
            guard !Task.isCancelled else { return }
            preview = result
            scanning = false
        }
    }

    private func exportRules() {
        guard let data = state.smartRules.exportActiveData() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(state.smartRules.activeRuleSet.name).\(SmartRuleStore.fileExtension)"
        panel.allowedContentTypes = [UTType(filenameExtension: SmartRuleStore.fileExtension) ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            state.toast = Toast(kind: .success, message: "Exported rule set")
        } catch {
            state.toast = Toast(kind: .failure, message: "Couldn't export rule set", detail: error.localizedDescription)
        }
    }

    private func importRules() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: SmartRuleStore.fileExtension) ?? .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let count = state.smartRules.importRuleSets(from: url)
        state.toast = count > 0
            ? Toast(kind: .success, message: "Imported \(count) rule set\(count == 1 ? "" : "s")")
            : Toast(kind: .failure, message: "Couldn't read rule set")
        rescan()
    }
}

private struct SmartRuleEditorRow: View {
    var rule: SmartStyleRule
    var order: Int
    var root: URL?
    var builtInPresets: [FolderStyle]
    var customPresets: [FolderStyle]
    var onChange: (SmartStyleRule) -> Void
    var onDelete: () -> Void
    var onMoveBefore: (UUID, UUID) -> Void

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryRow
            if isExpanded {
                Divider().padding(.vertical, 8)
                editor
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(isExpanded ? 0.28 : 0.14), in: RoundedRectangle(cornerRadius: 7))
        .onDrop(of: [.text], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadObject(ofClass: NSString.self) { value, _ in
                guard let raw = value as? String, let sourceID = UUID(uuidString: raw) else { return }
                DispatchQueue.main.async { onMoveBefore(sourceID, rule.id) }
            }
            return true
        }
    }

    private var summaryRow: some View {
        HStack(spacing: 8) {
            Text(String(format: "%02d", order))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 27, height: 24)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
                .onDrag { NSItemProvider(object: rule.id.uuidString as NSString) }
                .help("Drag to reorder")
            Toggle("", isOn: enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
            Button { withAnimation(.easeOut(duration: 0.14)) { isExpanded.toggle() } } label: {
                HStack(spacing: 9) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rule.kind.title)
                            .font(.system(size: 11, weight: .medium))
                        Text(conditionSummary)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 12)
                    if !rule.exclusionPatterns.isEmpty {
                        Label("\(rule.exclusionPatterns.count)", systemImage: "folder.badge.minus")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .help("\(rule.exclusionPatterns.count) excluded folder\(rule.exclusionPatterns.count == 1 ? "" : "s")")
                    }
                    Text(targetSummary)
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 94, alignment: .trailing)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text("Rule type")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .leading)
                Picker("Rule type", selection: kind) {
                    ForEach(SmartRuleKind.allCases) { kind in Text(kind.title).tag(kind) }
                }
                .frame(width: 140)

                if rule.kind == .folderName || rule.kind == .relativePath {
                    Text("Match")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Picker("Match", selection: match) {
                        ForEach(FolderNameMatch.allCases) { match in Text(match.title).tag(match) }
                    }
                    .frame(width: 108)
                }
            }

            HStack(spacing: 7) {
                Text(rule.kind == .fileTypeMajority ? "Extensions" : "Pattern")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .leading)
                TextField(patternPlaceholder, text: pattern)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
            }

            HStack(spacing: 7) {
                Text("Style")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .leading)
                Picker("Style source", selection: styleSource) {
                    ForEach(SmartRuleStyleSource.allCases) { source in
                        Text(source == .custom && customPresets.isEmpty ? "My Styles (0)" : source.title)
                            .tag(source)
                            .disabled(source == .custom && customPresets.isEmpty)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
                styleMenu
            }

            if rule.resolvedStyleSource == .custom, customPresets.isEmpty {
                Text("Save a design under My Styles before using it in a rule.")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }

            if rule.kind == .fileTypeMajority {
                HStack(spacing: 8) {
                    Text("Threshold")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 74, alignment: .leading)
                    Text("At least")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Picker("Threshold", selection: threshold) {
                        ForEach(thresholdOptions, id: \.self) { value in
                            Text("\(Int((value * 100).rounded()))%").tag(value)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 78)
                    Text("of direct files use these extensions")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Text("Exclude")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 74, alignment: .leading)
                Button("Choose folders to exclude…") { chooseExclusions() }
                    .controlSize(.small)
                    .disabled(root == nil)
                if !rule.exclusionPatterns.isEmpty {
                    exclusionMenu
                    Text("\(rule.exclusionPatterns.count) excluded")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Delete rule", role: .destructive, action: onDelete)
                    .controlSize(.small)
            }
        }
    }

    private var enabled: Binding<Bool> { binding(\.isEnabled) }
    private var kind: Binding<SmartRuleKind> {
        Binding(get: { rule.kind }, set: { value in
            var copy = rule
            copy.kind = value
            onChange(copy)
        })
    }
    private var match: Binding<FolderNameMatch> { binding(\.match) }
    private var presetName: Binding<String> { binding(\.presetName) }
    private var threshold: Binding<Double> { binding(\.threshold) }
    private var styleSource: Binding<SmartRuleStyleSource> {
        Binding(get: { rule.resolvedStyleSource }, set: { source in
            var copy = rule
            copy.styleSource = source
            let choices = source == .custom ? customPresets : builtInPresets
            if let first = choices.first, !choices.contains(where: { $0.name == copy.presetName }) {
                copy.presetName = first.name
            }
            onChange(copy)
        })
    }
    private var pattern: Binding<String> {
        Binding(get: {
            rule.kind == .fileTypeMajority ? rule.fileExtensions.joined(separator: ", ") : rule.pattern
        }, set: { value in
            var copy = rule
            if copy.kind == .fileTypeMajority {
                copy.fileExtensions = value.split(separator: ",").map(String.init)
            } else {
                copy.pattern = value
            }
            onChange(copy)
        })
    }
    private var patternPlaceholder: String {
        switch rule.kind {
        case .markerFile: "package.json, Package.swift"
        case .fileTypeMajority: "mp3, flac, wav"
        default: "Pattern"
        }
    }

    private var conditionSummary: String {
        switch rule.kind {
        case .markerFile:
            let count = FolderScanner.parsePatterns(rule.pattern).count
            return count <= 1 ? "Contains \(rule.pattern)" : "Contains any of \(count) project markers"
        case .fileTypeMajority:
            return "\(Int((rule.threshold * 100).rounded()))% of \(rule.fileExtensions.joined(separator: ", ")) files"
        case .folderName:
            return "Name \(rule.match.title.lowercased()) \(rule.pattern)"
        case .relativePath:
            return "Path \(rule.match.title.lowercased()) \(rule.pattern)"
        }
    }

    private var availablePresets: [FolderStyle] {
        rule.resolvedStyleSource == .custom ? customPresets : builtInPresets
    }

    private var selectedPreset: FolderStyle? {
        availablePresets.first { $0.name == rule.presetName }
    }

    private var styleMenu: some View {
        Menu {
            ForEach(availablePresets) { preset in
                Button {
                    presetName.wrappedValue = preset.name
                } label: {
                    HStack(spacing: 8) {
                        FolderIconView(style: preset, side: 24)
                        Text(preset.name)
                        if preset.name == rule.presetName {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                if let selectedPreset {
                    FolderIconView(style: selectedPreset, side: 22)
                } else {
                    Image(systemName: "questionmark.folder")
                        .frame(width: 22, height: 22)
                        .foregroundStyle(.secondary)
                }
                Text(selectedPreset?.name ?? "Choose style")
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 182, height: 28)
            .padding(.horizontal, 8)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
        }
        .menuStyle(.borderlessButton)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var targetSummary: String {
        rule.resolvedStyleSource == .custom ? "My: \(rule.presetName)" : rule.presetName
    }

    private var thresholdOptions: [Double] {
        [0.10, 0.25, 0.40, 0.50, 0.60, 0.70, 0.80, 0.90, 1.00]
    }

    private var exclusionMenu: some View {
        Menu {
            ForEach(rule.exclusionPatterns, id: \.self) { path in
                Button("Remove \(path)") { removeExclusion(path) }
            }
            Divider()
            Button("Clear all exclusions", role: .destructive) { clearExclusions() }
        } label: {
            Label("Manage", systemImage: "folder.badge.minus")
        }
        .controlSize(.small)
        .help("Manage excluded folders")
    }

    private func chooseExclusions() {
        guard let root else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = root
        panel.message = "Choose folders inside \(root.lastPathComponent) to exclude"
        panel.prompt = "Exclude"
        guard panel.runModal() == .OK else { return }

        let rootPath = root.standardizedFileURL.path
        let additions = panel.urls.compactMap { url -> String? in
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootPath + "/") else { return nil }
            return String(path.dropFirst(rootPath.count + 1))
        }
        guard !additions.isEmpty else { return }
        var copy = rule
        copy.exclusionPatterns = Array(Set(copy.exclusionPatterns + additions)).sorted()
        onChange(copy)
    }

    private func removeExclusion(_ path: String) {
        var copy = rule
        copy.exclusionPatterns.removeAll { $0 == path }
        onChange(copy)
    }

    private func clearExclusions() {
        var copy = rule
        copy.exclusionPatterns = []
        onChange(copy)
    }

    private func binding<T>(_ keyPath: WritableKeyPath<SmartStyleRule, T>) -> Binding<T> {
        Binding(get: { rule[keyPath: keyPath] }, set: { value in
            var copy = rule
            copy[keyPath: keyPath] = value
            onChange(copy)
        })
    }
}

/// SwiftUI's stock DisclosureGroup only gives the chevron a reliable toggle hit target in
/// this dense sheet. This makes the entire label row behave like a normal expandable section.
private struct FullWidthDisclosure<Label: View, Content: View>: View {
    @Binding var isExpanded: Bool
    @ViewBuilder var label: () -> Label
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.14)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                    label()
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            if isExpanded { content() }
        }
    }
}
