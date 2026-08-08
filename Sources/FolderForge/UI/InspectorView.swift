import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InspectorView: View {
    @Bindable var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $state.inspectorTab) {
                ForEach(AppState.InspectorTab.allCases) { tab in
                    Label(tab.title, systemImage: tab.symbol).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch state.inspectorTab {
                    case .color: ColorTab(style: $state.style)
                    case .icon: IconTab(state: state)
                    case .tune: TuneTab(style: $state.style)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        // Width is owned by the split view column, not hard-coded here — otherwise the
        // inspector gets clipped instead of resized when the window is narrow.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Color

private struct ColorTab: View {
    @Binding var style: FolderStyle

    var body: some View {
        SectionLabel(text: "Tint", symbol: "drop.fill")
        TintWell(color: $style.tint, label: style.gradientEnabled ? "From" : "Color")

        Toggle(isOn: $style.gradientEnabled) {
            Text("Gradient").font(.system(size: 12))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)

        if style.gradientEnabled {
            TintWell(color: $style.tintSecondary, label: "To")
            LabeledSlider(title: "Angle", value: $style.gradientAngle,
                          range: 0...360, defaultValue: 90, format: "%.0f°",
                          symbol: "angle")

            SectionLabel(text: "Gradient Presets")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 6)], spacing: 6) {
                ForEach(Palettes.gradients, id: \.name) { preset in
                    Button {
                        style.tint = RGBA(hex: preset.from) ?? style.tint
                        style.tintSecondary = RGBA(hex: preset.to) ?? style.tintSecondary
                        style.gradientAngle = preset.angle
                    } label: {
                        LinearGradient(
                            colors: [RGBA(hex: preset.from)!.color, RGBA(hex: preset.to)!.color],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(height: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .overlay {
                            Text(preset.name)
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.white)
                                .shadow(radius: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }

        Divider()

        SectionLabel(text: "Palettes", symbol: "swatchpalette")
        ForEach(Palettes.groups) { group in
            VStack(alignment: .leading, spacing: 5) {
                Text(group.name)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                SwatchGrid(swatches: group.swatches, selected: style.tint) { picked in
                    style.tint = picked
                }
            }
        }

        Divider()

        SectionLabel(text: "Strength", symbol: "dial.medium")
        LabeledSlider(title: "Tint amount", value: $style.tintStrength,
                      range: 0...1, defaultValue: 1, format: "%.0f%%", displayScale: 100)
        Text("Pull this down to blend back toward the stock macOS blue.")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)

        Toggle(isOn: $style.matchLuminance) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Match brightness").font(.system(size: 12))
                Text("Lets very dark and very pale colors actually land")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)

    }
}

// MARK: - Icon

private struct IconTab: View {
    @Bindable var state: AppState
    @State private var imageDropTargeted = false
    @State private var showingFullSymbolPicker = false

    private var style: Binding<FolderStyle> { $state.style }

    var body: some View {
        SectionLabel(text: "Overlay", symbol: "star")
        Picker("", selection: style.overlay.kind) {
            ForEach(OverlayKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: state.style.overlay.kind) { _, kind in
            // Emoji and images carry their own colors. Leaving a masked finish selected
            // turns them into a flat white silhouette, which nobody is asking for.
            switch kind {
            case .emoji, .image:
                state.style.fullIconData = nil
                if state.style.finish.isMasked { state.style.finish = .natural }
            case .symbol, .text:
                state.style.fullIconData = nil
                if state.style.finish == .natural { state.style.finish = .engraved }
            case .none:
                state.style.fullIconData = nil
            case .icns:
                state.style.overlay.imageData = nil
            }
        }

        switch state.style.overlay.kind {
        case .none:
            Text("A plain colored folder. Sometimes that's the whole point.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

        case .symbol:
            TextField("Type an SF Symbol name", text: style.overlay.symbolName)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .padding(.bottom, 6)

            SectionLabel(text: "Default symbols", symbol: "sparkles")
            DefaultSymbolRow(selection: style.overlay.symbolName)

            HStack(spacing: 10) {
                Text("Full SF Symbols")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Button {
                    showingFullSymbolPicker = true
                } label: {
                    Label("Browse all symbols", systemImage: "rectangle.grid.2x2")
                }
                .buttonStyle(.accessoryBar)
            }

            SymbolPicker(selection: style.overlay.symbolName)
                .padding(.bottom, 4)

            Picker("Weight", selection: style.symbolWeight) {
                ForEach(FolderStyle.SymbolWeight.allCases) { weight in
                    Text(weight.title).tag(weight)
                }
            }
            .controlSize(.small)
            .sheet(isPresented: $showingFullSymbolPicker) {
                FullSymbolBrowser(selection: style.overlay.symbolName)
                    .frame(minWidth: 700, minHeight: 520)
            }

        case .emoji:
            EmojiPicker(selection: style.overlay.emoji)

        case .text:
            TextField("Up to a few characters", text: style.overlay.text)
                .textFieldStyle(.roundedBorder)
            Picker("Weight", selection: style.symbolWeight) {
                ForEach(FolderStyle.SymbolWeight.allCases) { weight in
                    Text(weight.title).tag(weight)
                }
            }
            .controlSize(.small)

        case .image:
            imageWell

        case .icns:
            importedFullIconWell
        }

        if state.style.overlay.kind != .none && state.style.overlay.kind != .icns {
            Divider()

            SectionLabel(text: "Finish", symbol: "paintbrush")
            Picker("", selection: style.finish) {
                ForEach(OverlayFinish.allCases) { finish in
                    Text(finish.title).tag(finish)
                }
            }
            .labelsHidden()
            Text(state.style.finish.help)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            if state.style.finish.isMasked {
                TintWell(color: style.overlayColor, label: "Ink")
                HStack(spacing: 6) {
                    Button("White") { state.style.overlayColor = .white }
                    Button("Black") { state.style.overlayColor = .black }
                    Button("Folder Tint") { state.style.overlayColor = state.style.tint }
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }

            Toggle(isOn: style.overlayShadow) {
                Text("Drop shadow").font(.system(size: 12))
            }
            .toggleStyle(.switch)
            .controlSize(.mini)
            .disabled(state.style.finish == .stamped)

            Divider()

            SectionLabel(text: "Placement", symbol: "move.3d")
            LabeledSlider(title: "Size", value: style.overlayScale,
                          range: 0.15...0.75, defaultValue: 0.42, format: "%.0f%%",
                          symbol: "arrow.up.left.and.arrow.down.right", displayScale: 100)
            LabeledSlider(title: "Opacity", value: style.overlayOpacity,
                          range: 0...1, defaultValue: 0.92, format: "%.0f%%",
                          symbol: "circle.lefthalf.filled", displayScale: 100)
            LabeledSlider(title: "Horizontal", value: style.overlayOffsetX,
                          range: -0.3...0.3, defaultValue: 0, format: "%+.2f",
                          symbol: "arrow.left.and.right")
            LabeledSlider(title: "Vertical", value: style.overlayOffsetY,
                          range: -0.3...0.3, defaultValue: 0, format: "%+.2f",
                          symbol: "arrow.up.and.down")
            LabeledSlider(title: "Rotation", value: style.overlayRotation,
                          range: -180...180, defaultValue: 0, format: "%.0f°",
                          symbol: "rotate.right")
        }
    }

    private var importedFullIconWell: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Imported Icon", symbol: "app.dashed")

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.4))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        imageDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: imageDropTargeted ? 2 : 1, dash: [5, 3])
                    )

                if let data = state.style.fullIconData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else {
                    VStack(spacing: 5) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("Drop an ICNS")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Applies as the whole folder icon")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(height: 140)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                return loadImage(from: url)
            } isTargeted: { imageDropTargeted = $0 }

            Text("This ICNS will be applied as the whole folder icon.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            HStack(spacing: 6) {
                Button("Choose…") { chooseImage() }
                Button("Use Folder Canvas") {
                    state.style.fullIconData = nil
                    state.style.overlay.kind = .none
                }
            }
            .controlSize(.small)
        }
    }

    private var imageWell: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.4))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        imageDropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: imageDropTargeted ? 2 : 1, dash: [5, 3])
                    )

                if let data = state.style.overlay.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else {
                    VStack(spacing: 5) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("Drop an image")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("PNG or ICNS works best")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(height: 120)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                return loadImage(from: url)
            } isTargeted: { imageDropTargeted = $0 }

            HStack(spacing: 6) {
                Button("Choose…") { chooseImage() }
                if state.style.overlay.imageData != nil {
                    Button("Clear") { state.style.overlay.imageData = nil }
                }
            }
            .controlSize(.small)
        }
    }

    @discardableResult
    private func loadImage(from url: URL) -> Bool {
        guard let png = IconImport.pngData(from: url) else {
            state.toast = Toast(kind: .failure, message: "Couldn't read that image or icon")
            return false
        }
        if IconImport.isICNS(url) {
            state.style.fullIconData = png
            state.style.overlay.imageData = nil
            state.style.overlay.kind = .icns
            state.toast = Toast(kind: .success, message: "Imported \(url.lastPathComponent)")
            return true
        }
        state.style.fullIconData = nil
        state.style.overlay.imageData = png
        state.style.overlay.kind = .image
        // Photos and logos want their own colors.
        if state.style.finish.isMasked { state.style.finish = .natural }
        return true
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = IconImport.allowedContentTypes
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadImage(from: url)
    }
}

// MARK: - Tune

private struct TuneTab: View {
    @Binding var style: FolderStyle

    var body: some View {
        SectionLabel(text: "Tone", symbol: "camera.filters")
        LabeledSlider(title: "Saturation", value: $style.saturation,
                      range: 0...2, defaultValue: 1, symbol: "drop.halffull")
        LabeledSlider(title: "Brightness", value: $style.brightness,
                      range: -0.35...0.35, defaultValue: 0, format: "%+.2f",
                      symbol: "sun.max")
        LabeledSlider(title: "Contrast", value: $style.contrast,
                      range: 0.6...1.6, defaultValue: 1, symbol: "circle.righthalf.filled")

        Button {
            style.saturation = 1
            style.brightness = 0
            style.contrast = 1
        } label: {
            Label("Reset Tone", systemImage: "arrow.uturn.backward")
        }
        .controlSize(.small)
        .buttonStyle(.bordered)

        Divider()

        SectionLabel(text: "Looks", symbol: "wand.and.stars")
        VStack(spacing: 6) {
            lookButton("Vintage", saturation: 0.55, brightness: 0.04, contrast: 0.9)
            lookButton("Punchy", saturation: 1.45, brightness: 0.0, contrast: 1.15)
            lookButton("Pastel", saturation: 0.6, brightness: 0.16, contrast: 0.92)
            lookButton("Noir", saturation: 0.0, brightness: -0.05, contrast: 1.2)
            lookButton("Neon", saturation: 1.8, brightness: 0.05, contrast: 1.25)
        }

        Divider()

        SectionLabel(text: "Name", symbol: "textformat")
        TextField("Style name", text: $style.name)
            .textFieldStyle(.roundedBorder)
        Text("Used when you save this as a preset.")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
    }

    private func lookButton(_ name: String,
                            saturation: Double,
                            brightness: Double,
                            contrast: Double) -> some View {
        let isActive = abs(style.saturation - saturation) < 0.01
            && abs(style.brightness - brightness) < 0.01
            && abs(style.contrast - contrast) < 0.01

        return Button {
            style.saturation = saturation
            style.brightness = brightness
            style.contrast = contrast
        } label: {
            HStack {
                Text(name).font(.system(size: 11))
                Spacer()
                if isActive {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.09))
            }
        }
        .buttonStyle(.plain)
    }
}
