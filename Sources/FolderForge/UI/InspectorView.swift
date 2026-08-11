import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct InspectorView: View {
    @Bindable var state: AppState

    private var locksCurrentTab: Bool {
        state.style.fill.kind == .icns && state.style.fill.fullIconData != nil && state.inspectorTab != .fill
    }

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
                    if locksCurrentTab {
                        LockedForICNSView(tab: state.inspectorTab)
                    } else {
                        switch state.inspectorTab {
                        case .color: ColorTab(style: $state.style)
                        case .fill: FillTab(state: state)
                        case .icon: IconTab(state: state)
                        case .tune: TuneTab(style: $state.style)
                        }
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

private struct LockedForICNSView: View {
    var tab: AppState.InspectorTab

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "\(tab.title) Disabled", symbol: "lock.fill")
            Text("ICNS fill replaces the entire folder icon, so color, overlays and tuning do not apply.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Switch Fill back to Color or Image to use the other tabs.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Color

private struct ColorTab: View {
    @Binding var style: FolderStyle

    private var primaryTint: Binding<RGBA> {
        Binding(
            get: { style.tint },
            set: {
                style.tint = $0
                style.tintStrength = 1
            }
        )
    }

    private var secondaryTint: Binding<RGBA> {
        Binding(
            get: { style.tintSecondary },
            set: {
                style.tintSecondary = $0
                style.tintStrength = 1
            }
        )
    }

    private func layerBinding(
        _ keyPath: WritableKeyPath<FolderStyle, NativeFolderLayerStyle>
    ) -> Binding<NativeFolderLayerStyle> {
        Binding(
            get: { style[keyPath: keyPath] },
            set: { style[keyPath: keyPath] = $0 }
        )
    }

    var body: some View {
        SectionLabel(text: style.separateLayerColors ? "Native Layers" : "Tint",
                     symbol: style.separateLayerColors ? "square.3.layers.3d" : "drop.fill")

        if style.baseIcon == .generic {
            separateLayersToggle
            if style.separateLayerColors { Divider() }
        }

        if style.baseIcon == .generic && style.separateLayerColors {
            LayerFillEditor(title: "Back", symbol: "rectangle.stack",
                            layer: layerBinding(\.backLayer), canHide: true)
            LayerFillEditor(title: "Paper", symbol: "doc",
                            layer: layerBinding(\.paperLayer), canHide: true)
            LayerFillEditor(title: "Front", symbol: "rectangle.fill",
                            layer: layerBinding(\.frontLayer), canHide: false)
        } else {
            linkedColorControls
        }

        if !(style.baseIcon == .generic && style.separateLayerColors) {
            Divider()

            SectionLabel(text: "Palettes", symbol: "swatchpalette")
            ForEach(Palettes.groups) { group in
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.name)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    SwatchGrid(swatches: group.swatches, selected: style.tint) { picked in
                        style.tint = picked
                        style.tintStrength = 1
                    }
                }
            }
        }

        Divider()

        SectionLabel(text: "Strength", symbol: "dial.medium")
        LabeledSlider(title: "Tint amount", value: $style.tintStrength,
                      range: 0...1, defaultValue: 1, format: "%.0f%%", displayScale: 100)
        Text("Pull this down to blend back toward the stock macOS colors.")
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

    private var separateLayersToggle: some View {
        Toggle(isOn: $style.separateLayerColors) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Customize layers separately").font(.system(size: 12))
                Text("Independent fills for the back, paper, and front")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .onChange(of: style.separateLayerColors) { _, enabled in
            guard enabled else { return }
            let defaults = FolderStyle()
            if style.backLayer == defaults.backLayer,
               style.paperLayer == defaults.paperLayer,
               style.frontLayer == defaults.frontLayer {
                style.backLayer.tint = style.tint
                style.backLayer.tintSecondary = style.tintSecondary
                style.frontLayer.tint = style.tint
                style.frontLayer.tintSecondary = style.tintSecondary
                style.paperLayer.tint = .white
            }
            style.tintStrength = 1
        }
    }

    @ViewBuilder
    private var linkedColorControls: some View {
        TintWell(color: primaryTint, label: style.gradientEnabled ? "From" : "Color")

        Toggle(isOn: $style.gradientEnabled) {
            Text("Gradient").font(.system(size: 12))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)

        if style.gradientEnabled {
            TintWell(color: secondaryTint, label: "To")
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
                        style.tintStrength = 1
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
    }
}

private struct LayerFillEditor: View {
    var title: String
    var symbol: String
    @Binding var layer: NativeFolderLayerStyle
    var canHide: Bool
    @State private var dropTargeted = false

    private var primaryTint: Binding<RGBA> {
        Binding(get: { layer.tint }, set: { layer.tint = $0 })
    }

    private var secondaryTint: Binding<RGBA> {
        Binding(get: { layer.tintSecondary }, set: { layer.tintSecondary = $0 })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .frame(width: 16)
                    .foregroundStyle(layer.enabled ? Color.accentColor : .secondary)
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                if canHide {
                    Toggle("", isOn: $layer.enabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .help("Show or hide the \(title.lowercased()) layer")
                } else {
                    Text("Always on")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }

            if layer.enabled || !canHide {
                Picker("", selection: $layer.fillKind) {
                    ForEach(NativeLayerFillKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)

                switch layer.fillKind {
                case .color:
                    colorControls
                case .image:
                    imageControls
                }
            } else {
                Text("Hidden from the rendered folder")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(11)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
    }

    private var colorControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            TintWell(color: primaryTint, label: layer.gradientEnabled ? "From" : "Color")
            Toggle("Gradient", isOn: $layer.gradientEnabled)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 11))
            if layer.gradientEnabled {
                TintWell(color: secondaryTint, label: "To")
                LabeledSlider(title: "Angle", value: $layer.gradientAngle,
                              range: 0...360, defaultValue: 90, format: "%.0f°",
                              symbol: "angle")
            }
        }
    }

    private var imageControls: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(.black.opacity(0.12))
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(dropTargeted ? Color.accentColor : .secondary.opacity(0.3),
                                  style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1,
                                                     dash: [5, 3]))
                if let data = layer.imageData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                        .padding(5)
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 18, weight: .light))
                        Text("Drop an image")
                            .font(.system(size: 10))
                    }
                    .foregroundStyle(.tertiary)
                }
            }
            .frame(height: 82)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                return loadImage(from: url)
            } isTargeted: { dropTargeted = $0 }

            HStack(spacing: 6) {
                Button("Choose…") { chooseImage() }
                if layer.imageData != nil {
                    Button("Clear") { layer.imageData = nil }
                }
            }
            .controlSize(.small)

            LabeledSlider(title: "Size", value: $layer.imageScale,
                          range: 0.15...2.4, defaultValue: 1,
                          format: "%.0f%%", displayScale: 100)
            LabeledSlider(title: "Opacity", value: $layer.imageOpacity,
                          range: 0...1, defaultValue: 1,
                          format: "%.0f%%", displayScale: 100)
            LabeledSlider(title: "Horizontal", value: $layer.imageOffsetX,
                          range: -0.3...0.3, defaultValue: 0, format: "%+.2f")
            LabeledSlider(title: "Vertical", value: $layer.imageOffsetY,
                          range: -0.3...0.3, defaultValue: 0, format: "%+.2f")
            LabeledSlider(title: "Rotation", value: $layer.imageRotation,
                          range: -180...180, defaultValue: 0, format: "%.0f°")
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = IconImport.imageContentTypes
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        _ = loadImage(from: url)
    }

    @discardableResult
    private func loadImage(from url: URL) -> Bool {
        guard !IconImport.isICNS(url), let png = IconImport.pngData(from: url) else {
            return false
        }
        layer.imageData = png
        layer.fillKind = .image
        return true
    }
}

// MARK: - Fill

private struct FillTab: View {
    @Bindable var state: AppState
    @State private var dropTargeted = false
    @State private var dragStartOffset: CGPoint?

    private var style: Binding<FolderStyle> { $state.style }

    private enum ImagePlacementMode: String, CaseIterable, Identifiable {
        case fit, fill
        var id: String { rawValue }
        var title: String {
            switch self {
            case .fit: "Fit"
            case .fill: "Fill"
            }
        }
    }

    private var imagePlacementMode: Binding<ImagePlacementMode> {
        Binding {
            state.style.fillScale < 0.95 ? .fit : .fill
        } set: { mode in
            switch mode {
            case .fit: setImagePlacement(scale: 0.72)
            case .fill: setImagePlacement(scale: 1.0)
            }
        }
    }

    var body: some View {
        SectionLabel(text: "Fill", symbol: "paintbrush.pointed")
        Picker("", selection: style.fill.kind) {
            ForEach(FillKind.allCases) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: state.style.fill.kind) { _, kind in
            switch kind {
            case .color:
                state.style.fill.imageData = nil
                state.style.fill.fullIconData = nil
            case .image:
                state.style.fill.fullIconData = nil
            case .icns:
                state.style.fill.imageData = nil
            }
        }

        switch state.style.fill.kind {
        case .color:
            Text("Uses the color and gradient from the Color tab.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)

        case .image:
            imageWell
            Divider()
            imagePlacementControls

        case .icns:
            importedFullIconWell
        }
    }

    private var imageWell: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.4))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [5, 3])
                    )

                if state.style.fill.imageData != nil {
                    GeometryReader { geometry in
                        FolderIconView(style: state.style, side: 96)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(imageDragGesture(in: geometry.size))
                    }
                } else {
                    VStack(spacing: 5) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("Drop an image")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("PNG or JPG fills the folder face")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(height: 120)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                return loadFill(from: url)
            } isTargeted: { dropTargeted = $0 }

            HStack(spacing: 6) {
                Button("Choose…") { chooseFill() }
                if state.style.fill.imageData != nil {
                    Button("Clear") {
                        state.style.fill.kind = .color
                        state.style.fill.imageData = nil
                    }
                }
            }
            .controlSize(.small)
        }
    }

    private var importedFullIconWell: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Imported ICNS", symbol: "app.badge.checkmark")

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.4))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        dropTargeted ? Color.accentColor : Color.secondary.opacity(0.35),
                        style: StrokeStyle(lineWidth: dropTargeted ? 2 : 1, dash: [5, 3])
                    )

                if let data = state.style.fill.fullIconData, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(10)
                } else {
                    VStack(spacing: 5) {
                        Image(systemName: "app.badge.checkmark")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("Drop an ICNS")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text("Replaces the whole folder icon")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(height: 140)
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                return loadFill(from: url)
            } isTargeted: { dropTargeted = $0 }

            Text("ICNS fills replace the whole folder. Symbols, emoji and text overlays stay available for image fills.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            HStack(spacing: 6) {
                Button("Choose…") { chooseFill() }
            }
            .controlSize(.small)
        }
    }

    private var imagePlacementControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Image Placement", symbol: "move.3d")
            Picker("", selection: imagePlacementMode) {
                ForEach(ImagePlacementMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            LabeledSlider(title: "Size", value: style.fillScale,
                          range: 0.15...2.4, defaultValue: 1.0,
                          format: "%.0f%%",
                          symbol: "arrow.up.left.and.arrow.down.right", displayScale: 100)
            LabeledSlider(title: "Opacity", value: style.fillOpacity,
                          range: 0...1, defaultValue: 1.0,
                          format: "%.0f%%",
                          symbol: "circle.lefthalf.filled", displayScale: 100)
            LabeledSlider(title: "Horizontal", value: style.fillOffsetX,
                          range: -0.3...0.3, defaultValue: 0, format: "%+.2f",
                          symbol: "arrow.left.and.right")
            LabeledSlider(title: "Vertical", value: style.fillOffsetY,
                          range: -0.3...0.3, defaultValue: 0, format: "%+.2f",
                          symbol: "arrow.up.and.down")
            Button {
                setImagePlacement(scale: 1.0)
            } label: {
                Label("Reset Image Placement", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)
            .buttonStyle(.bordered)
        }
    }

    @discardableResult
    private func loadFill(from url: URL) -> Bool {
        let isICNS = IconImport.isICNS(url)
        switch state.style.fill.kind {
        case .color:
            state.toast = Toast(kind: .failure, message: "Choose Image or ICNS first")
            return false
        case .image where isICNS:
            state.toast = Toast(kind: .failure, message: "Image fill only accepts image files")
            return false
        case .icns where !isICNS:
            state.toast = Toast(kind: .failure, message: "ICNS fill only accepts .icns files")
            return false
        default:
            break
        }

        guard let png = IconImport.pngData(from: url) else {
            state.toast = Toast(kind: .failure, message: "Couldn't read that file")
            return false
        }

        if isICNS {
            state.style.fill.kind = .icns
            state.style.fill.fullIconData = png
            state.style.fill.imageData = nil
        } else {
            state.style.fill.kind = .image
            state.style.fill.imageData = png
            state.style.fill.fullIconData = nil
            setImagePlacement(scale: 1.0)
        }
        state.toast = Toast(kind: .success, message: "Imported \(url.lastPathComponent)")
        return true
    }

    private func chooseFill() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = switch state.style.fill.kind {
        case .image: IconImport.imageContentTypes
        case .icns: [IconImport.icnsType]
        case .color: IconImport.allowedContentTypes
        }
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadFill(from: url)
    }

    private func setImagePlacement(scale: Double) {
        state.style.fillScale = scale
        state.style.fillOpacity = 1.0
        state.style.fillOffsetX = 0
        state.style.fillOffsetY = 0
        state.style.fillRotation = 0
    }

    private func imageDragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartOffset == nil {
                    dragStartOffset = CGPoint(x: state.style.fillOffsetX,
                                              y: state.style.fillOffsetY)
                }
                let base = dragStartOffset ?? .zero
                let divisor = max(min(size.width, size.height), 1)
                state.style.fillOffsetX = clamp(Double(base.x + value.translation.width / divisor))
                state.style.fillOffsetY = clamp(Double(base.y - value.translation.height / divisor))
            }
            .onEnded { _ in dragStartOffset = nil }
    }

    private func clamp(_ value: Double) -> Double {
        min(0.3, max(-0.3, value))
    }
}

// MARK: - Icon

private struct IconTab: View {
    @Bindable var state: AppState
    @State private var imageDropTargeted = false
    @State private var showingFullSymbolPicker = false
    @State private var dragStartOffset: CGPoint?

    private var style: Binding<FolderStyle> { $state.style }
    private let overlayKinds: [OverlayKind] = [.none, .symbol, .emoji, .text, .appIcon]

    private enum ImagePlacementMode: String, CaseIterable, Identifiable {
        case fit, fill
        var id: String { rawValue }
        var title: String {
            switch self {
            case .fit: "Fit"
            case .fill: "Fill"
            }
        }
    }

    private var imagePlacementMode: Binding<ImagePlacementMode> {
        Binding {
            state.style.overlayScale < 0.95 ? .fit : .fill
        } set: { mode in
            switch mode {
            case .fit: setImagePlacement(scale: 0.72)
            case .fill: setImagePlacement(scale: 1.0)
            }
        }
    }

    var body: some View {
        SectionLabel(text: "Overlay", symbol: "sparkles")
        Picker("", selection: style.overlay.kind) {
            ForEach(overlayKinds) { kind in
                Text(kind.title).tag(kind)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .onChange(of: state.style.overlay.kind) { _, kind in
            switch kind {
            case .emoji, .appIcon:
                if state.style.finish.isMasked { state.style.finish = .natural }
            case .symbol, .text:
                if state.style.finish == .natural { state.style.finish = .engraved }
            case .none, .image, .icns:
                break
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

        case .appIcon:
            applicationIconWell

        case .image, .icns:
            Text("Images and ICNS imports now live in the Fill tab.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }

        if overlayKinds.contains(state.style.overlay.kind), state.style.overlay.kind != .none {
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
                          range: 0.15...0.75,
                          defaultValue: 0.42,
                          format: "%.0f%%",
                          symbol: "arrow.up.left.and.arrow.down.right", displayScale: 100)
            LabeledSlider(title: "Opacity", value: style.overlayOpacity,
                          range: 0...1,
                          defaultValue: 0.92,
                          format: "%.0f%%",
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

    private var applicationIconWell: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary.opacity(0.4))
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.secondary.opacity(0.3))

                if let data = state.style.overlay.imageData,
                   let image = NSImage(data: data) {
                    VStack(spacing: 6) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                        if let name = state.style.overlay.sourceAppName {
                            Text(name)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                        }
                    }
                    .padding(10)
                } else {
                    VStack(spacing: 5) {
                        Image(systemName: "app.dashed")
                            .font(.system(size: 24, weight: .light))
                            .foregroundStyle(.tertiary)
                        Text("Choose an application")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 126)

            HStack(spacing: 6) {
                Button("Choose Application…") { chooseApplication() }
                if state.style.overlay.imageData != nil {
                    Button("Clear") {
                        state.style.overlay.imageData = nil
                        state.style.overlay.sourceAppName = nil
                    }
                }
            }
            .controlSize(.small)

            Text("The app icon is embedded in the preset and remains available if the app moves.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = IconImport.applicationContentTypes
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let imported = IconImport.applicationIcon(from: url) else {
            state.toast = Toast(kind: .failure, message: "Couldn't read that application icon")
            return
        }

        state.style.overlay.kind = .appIcon
        state.style.overlay.imageData = imported.pngData
        state.style.overlay.sourceAppName = imported.name
        state.style.finish = .natural
        state.style.overlayShadow = true
        setImagePlacement(scale: 0.42)
        state.toast = Toast(kind: .success, message: "Using the \(imported.name) icon")
    }

    private var importedFullIconWell: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Imported Icon", symbol: "app.badge.checkmark")

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
                        Image(systemName: "app.badge.checkmark")
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

                if state.style.overlay.imageData != nil {
                    GeometryReader { geometry in
                        FolderIconView(style: state.style, side: 96)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .gesture(imageDragGesture(in: geometry.size))
                    }
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
        setImagePlacement(scale: 1.0)
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

    private func setImagePlacement(scale: Double) {
        state.style.overlayScale = scale
        state.style.overlayOpacity = 1.0
        state.style.overlayOffsetX = 0
        state.style.overlayOffsetY = 0
        state.style.overlayRotation = 0
    }

    private func imageDragGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if dragStartOffset == nil {
                    dragStartOffset = CGPoint(x: state.style.overlayOffsetX,
                                              y: state.style.overlayOffsetY)
                }
                let base = dragStartOffset ?? .zero
                let divisor = max(min(size.width, size.height), 1)
                state.style.overlayOffsetX = clamp(Double(base.x + value.translation.width / divisor))
                state.style.overlayOffsetY = clamp(Double(base.y - value.translation.height / divisor))
            }
            .onEnded { _ in dragStartOffset = nil }
    }

    private func clamp(_ value: Double) -> Double {
        min(0.3, max(-0.3, value))
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
