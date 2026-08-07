import AppKit
import SwiftUI

struct PreviewPane: View {
    @Bindable var state: AppState

    private var displayed: FolderStyle {
        state.showingOriginal ? AppState.plainStyle(base: state.style.baseIcon) : state.style
    }

    /// While comparing, show the selected folder's *real* icon straight from disk rather than
    /// a generic stock folder — that's the thing the new design is actually replacing.
    private var comparisonIcon: NSImage? {
        guard state.showingOriginal,
              state.selectedFolders.count == 1,
              let item = state.selectedFolders.first else { return nil }
        return IconApplier.currentIcon(of: item.url)
    }

    @ViewBuilder
    private func icon(side: CGFloat) -> some View {
        if let comparisonIcon {
            Image(nsImage: comparisonIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
        } else if state.previewShowsExistingIcon, let item = state.foreignIconFolder {
            // Its icon came from another tool, so there are no settings to load — but we can
            // at least show the truth rather than a stock folder that isn't what's on disk.
            Image(nsImage: IconApplier.currentIcon(of: item.url))
                .resizable()
                .interpolation(.high)
                .frame(width: side, height: side)
        } else {
            FolderIconView(style: displayed, side: side)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            // Budget the height explicitly. The stage has to be told what's left after the
            // gallery takes its cut — handed the full height it sizes the hero icon as if
            // the gallery weren't there, and the gallery gets pushed off the bottom.
            let galleryHeight: CGFloat = if geometry.size.height > 560 { 148 }
                else if geometry.size.height > 380 { 116 }
                else { 0 }
            let stageHeight = max(120, geometry.size.height - galleryHeight
                                  - (galleryHeight > 0 ? 1 : 0))

            VStack(spacing: 0) {
                stage(in: CGSize(width: geometry.size.width, height: stageHeight))
                    .frame(height: stageHeight)

                // The gallery is the first thing to give up room when the window is short.
                if galleryHeight > 0 {
                    Divider()
                    PresetGallery(state: state)
                        .frame(height: galleryHeight)
                }
            }
        }
    }

    // MARK: - Stage

    private func stage(in size: CGSize) -> some View {
        // Scale the hero icon to whatever room there actually is, so the pane never
        // demands more space than the window can give it.
        let available = min(size.width - 60, size.height - 190)
        let hero = max(72, min(220, available * 0.60)) * state.previewScale
        let roomForStrip = size.height > 380
        let roomForControls = size.height > 260

        return ZStack {
            backdrop

            VStack(spacing: size.height > 560 ? 22 : 14) {
                Spacer(minLength: 0)

                VStack(spacing: 6) {
                    icon(side: hero)
                    Text(state.previewName)
                        .font(.system(size: max(9, min(13, hero * 0.09))))
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: hero * 1.6)
                }
                .animation(.easeOut(duration: 0.12), value: state.previewScale)

                if state.previewShowsExistingIcon { existingIconNote }

                if roomForStrip { sizeStrip(width: size.width) }

                Spacer(minLength: 0)

                if roomForControls { controls }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var backdrop: some View {
        LinearGradient(
            colors: [Color(nsColor: .underPageBackgroundColor),
                     Color(nsColor: .windowBackgroundColor)],
            startPoint: .top, endPoint: .bottom
        )
        .overlay {
            // A faint grid so translucent and white folders stay readable.
            Canvas { context, size in
                let step: CGFloat = 22
                var path = Path()
                for x in stride(from: 0, through: size.width, by: step) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 0, through: size.height, by: step) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(path, with: .color(.gray.opacity(0.06)), lineWidth: 0.5)
            }
        }
        .ignoresSafeArea()
    }

    /// The sizes Finder actually draws folders at — the honest test of whether a design works.
    /// Drops the larger samples first when the pane gets narrow.
    private func sizeStrip(width: CGFloat) -> some View {
        let sizes: [Int] = if width > 460 { [128, 64, 32, 16] }
            else if width > 340 { [64, 32, 16] }
            else { [32, 16] }

        return HStack(alignment: .bottom, spacing: width > 460 ? 20 : 14) {
            ForEach(sizes, id: \.self) { size in
                VStack(spacing: 5) {
                    icon(side: CGFloat(size))
                    Text("\(size)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Shown when the selected folder's icon came from another tool.
    private var existingIconNote: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("This is the folder's existing icon")
                    .font(.system(size: 11, weight: .medium))
                Text("It wasn't made in FolderForge, so there are no settings to load. "
                     + "Start designing to replace it — Restore brings this one back.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: 380, alignment: .leading)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))
    }

    private var controls: some View {
        // Full control bar when there's room, zoom-only when there isn't.
        ViewThatFits(in: .horizontal) {
            controlBar(includeCompare: true)
            controlBar(includeCompare: false)
        }
    }

    private func controlBar(includeCompare: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "minus.magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            Slider(value: $state.previewScale, in: 0.5...1.8)
                .frame(width: includeCompare ? 130 : 100)
                .controlSize(.small)
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            if includeCompare {
                Divider().frame(height: 16)

                Button {
                } label: {
                    Label("Hold to Compare", systemImage: "square.on.square.dashed")
                        .font(.system(size: 11))
                }
                .buttonStyle(.accessoryBar)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in state.showingOriginal = true }
                        .onEnded { _ in state.showingOriginal = false }
                )
                .help("Press and hold to see the folder's current icon")
            }
        }
        .fixedSize()
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 0.5) }
    }
}

// MARK: - Preset gallery

struct PresetGallery: View {
    @Bindable var state: AppState
    @State private var showingUserPresets = false
    @State private var renaming: FolderStyle?
    @State private var renameText = ""

    private var shown: [FolderStyle] {
        showingUserPresets ? state.presets.userPresets : state.presets.builtIn
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if shown.isEmpty {
                emptyState
            } else {
                gallery
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        .sheet(item: $renaming) { preset in
            renameSheet(preset)
        }
    }

    private var header: some View {
        // Labels collapse to bare icons before anything gets clipped.
        ViewThatFits(in: .horizontal) {
            headerRow(showLabels: true)
            headerRow(showLabels: false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func headerRow(showLabels: Bool) -> some View {
        HStack(spacing: 10) {
            Picker("", selection: $showingUserPresets) {
                Text("Built-in").tag(false)
                Text(showLabels
                     ? "My Styles (\(state.presets.userPresets.count))"
                     : "Mine (\(state.presets.userPresets.count))").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: showLabels ? 220 : 150)

            Spacer(minLength: 4)

            Button {
                state.saveCurrentAsPreset()
                showingUserPresets = true
            } label: {
                adaptiveLabel("Save Current", "plus.rectangle.on.folder", showLabels)
            }
            .buttonStyle(.accessoryBar)
            .help("Save this design as a preset")

            Button { state.randomize() } label: {
                adaptiveLabel("Surprise Me", "dice", showLabels)
            }
            .buttonStyle(.accessoryBar)
            .help("Generate a random style")
        }
    }

    @ViewBuilder
    private func adaptiveLabel(_ title: String, _ symbol: String,
                               _ showLabel: Bool) -> some View {
        if showLabel {
            Label(title, systemImage: symbol).font(.system(size: 11))
        } else {
            Label(title, systemImage: symbol).font(.system(size: 11)).labelStyle(.iconOnly)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Text("No saved styles yet")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text("Design a folder, then hit Save Current.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gallery: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(shown) { preset in
                    presetTile(preset)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
    }

    private func presetTile(_ preset: FolderStyle) -> some View {
        let isCurrent = state.style.matchesAppearance(of: preset)
        return Button {
            state.load(preset: preset)
        } label: {
            VStack(spacing: 4) {
                FolderIconView(style: preset, side: 56)
                Text(preset.name)
                    .font(.system(size: 10))
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? Color.accentColor : .secondary)
            }
            .frame(width: 72)
            .padding(.vertical, 6)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrent ? Color.accentColor.opacity(0.12) : .clear)
            }
        }
        .buttonStyle(.plain)
        .help(preset.name)
        .contextMenu {
            if showingUserPresets {
                Button("Rename…") {
                    renameText = preset.name
                    renaming = preset
                }
                Button("Update to Current Design") {
                    var updated = state.style
                    updated.id = preset.id
                    updated.name = preset.name
                    state.presets.update(updated)
                }
                Divider()
                Button("Delete", role: .destructive) { state.presets.delete(preset) }
            } else {
                Button("Save a Copy to My Styles") {
                    state.presets.add(preset, named: preset.name)
                    showingUserPresets = true
                }
            }
        }
    }

    private func renameSheet(_ preset: FolderStyle) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rename Style").font(.headline)
            TextField("Name", text: $renameText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 240)
                .onSubmit {
                    state.presets.rename(preset, to: renameText)
                    renaming = nil
                }
            HStack {
                Spacer()
                Button("Cancel") { renaming = nil }
                Button("Rename") {
                    state.presets.rename(preset, to: renameText)
                    renaming = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }
}
