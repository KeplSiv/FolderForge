import AppKit
import SwiftUI

/// Keeps app-owned sheets and utility panels inside the usable area of the display.
/// The height allowance accounts for the menu bar, Dock, parent title bar, and the
/// point below the toolbar where an attached sheet begins.
enum DialogLayout {
    static func fittedSize(preferredWidth: CGFloat,
                           preferredHeight: CGFloat,
                           visibleWidth: CGFloat,
                           visibleHeight: CGFloat) -> CGSize {
        let safeWidth = max(1, visibleWidth)
        let safeHeight = max(1, visibleHeight)
        let availableWidth = min(safeWidth, max(360, safeWidth * 0.90))
        let availableHeight = min(safeHeight, max(420, safeHeight * 0.78))
        return CGSize(width: min(preferredWidth, availableWidth),
                      height: min(preferredHeight, availableHeight))
    }

    static func currentSize(preferredWidth: CGFloat,
                            preferredHeight: CGFloat) -> CGSize {
        let frame = NSApp.keyWindow?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(x: 0, y: 0, width: preferredWidth, height: preferredHeight)
        return fittedSize(preferredWidth: preferredWidth,
                          preferredHeight: preferredHeight,
                          visibleWidth: frame.width,
                          visibleHeight: frame.height)
    }
}

private struct ScreenFittedDialogModifier: ViewModifier {
    let preferredWidth: CGFloat
    let preferredHeight: CGFloat

    func body(content: Content) -> some View {
        let size = DialogLayout.currentSize(preferredWidth: preferredWidth,
                                            preferredHeight: preferredHeight)
        content.frame(width: size.width, height: size.height)
    }
}

extension View {
    func screenFittedDialog(width: CGFloat, height: CGFloat) -> some View {
        modifier(ScreenFittedDialogModifier(preferredWidth: width,
                                            preferredHeight: height))
    }
}

/// A labelled slider with a live numeric readout and a double-click-to-reset affordance.
struct LabeledSlider: View {
    var title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var defaultValue: Double
    var format: String = "%.2f"
    var symbol: String?
    /// Multiplier applied to the readout only — lets a 0…1 slider display as 0…100%.
    var displayScale: Double = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                }
                Text(LocalizedStringKey(title))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: format, value * displayScale))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                if abs(value - defaultValue) > 0.0001 {
                    Button {
                        value = defaultValue
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 9))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tertiary)
                    .help("Reset to \(String(format: format, defaultValue * displayScale))")
                }
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
    }
}

/// Section header used throughout the inspector.
struct SectionLabel: View {
    var text: String
    var symbol: String?

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            }
            Text(LocalizedStringKey(text))
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .textCase(.uppercase)
        }
        .foregroundStyle(.secondary)
    }
}

/// A grid of color chips.
struct SwatchGrid: View {
    var swatches: [Palettes.Swatch]
    var selected: RGBA
    var onPick: (RGBA) -> Void

    private let columns = [GridItem(.adaptive(minimum: 24, maximum: 24), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(swatches) { swatch in
                Button { onPick(swatch.color) } label: {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(swatch.color.color)
                        .frame(width: 24, height: 24)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(.white.opacity(0.25), lineWidth: 0.5)
                        }
                        .overlay {
                            if isSelected(swatch.color) {
                                RoundedRectangle(cornerRadius: 7)
                                    .strokeBorder(Color.accentColor, lineWidth: 2)
                                    .padding(-2.5)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(swatch.name)
            }
        }
    }

    private func isSelected(_ color: RGBA) -> Bool {
        abs(color.r - selected.r) < 0.01
            && abs(color.g - selected.g) < 0.01
            && abs(color.b - selected.b) < 0.01
    }
}

/// Hex text field that only commits when the value actually parses.
struct HexField: View {
    @Binding var color: RGBA
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Hex", text: $text)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11, design: .monospaced))
            .frame(width: 84)
            .focused($focused)
            .onSubmit(commit)
            .onChange(of: focused) { _, isFocused in
                if !isFocused { commit() }
            }
            .onAppear { text = color.hex }
            .onChange(of: color) { _, new in
                if !focused { text = new.hex }
            }
    }

    private func commit() {
        if let parsed = RGBA(hex: text) {
            color = parsed
        }
        text = color.hex
    }
}

/// Transient banner for success / failure messages.
struct ToastView: View {
    var toast: Toast

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(toast.message)).font(.system(size: 12, weight: .medium))
                if let detail = toast.detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: 420, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10).strokeBorder(.separator, lineWidth: 0.5)
        }
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }

    private var symbol: String {
        switch toast.kind {
        case .success: "checkmark.circle.fill"
        case .failure: "exclamationmark.triangle.fill"
        case .info: "info.circle.fill"
        }
    }

    private var tint: Color {
        switch toast.kind {
        case .success: .green
        case .failure: .orange
        case .info: .accentColor
        }
    }
}

/// NSColorPanel-backed well. SwiftUI's ColorPicker works, but this keeps the alpha channel
/// out of the picker (a folder tint with alpha makes no sense) and matches the row layout.
struct TintWell: View {
    @Binding var color: RGBA
    var label: String

    var body: some View {
        HStack(spacing: 8) {
            ColorPicker(selection: Binding(
                get: { color.color },
                set: { color = RGBA($0) }
            ), supportsOpacity: false) {
                Text(LocalizedStringKey(label))
            }
            .labelsHidden()
            .frame(width: 28, height: 24)
            .padding(4)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.35), in: RoundedRectangle(cornerRadius: 8))

            Text(LocalizedStringKey(label))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()
            HexField(color: $color)
        }
    }
}
