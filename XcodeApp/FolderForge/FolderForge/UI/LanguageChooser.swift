import SwiftUI

struct LanguageChooserView: View {
    @Bindable var state: AppState
    var firstRun: Bool

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "character.bubble.fill")
                .font(.system(size: 40))
                .foregroundStyle(.tint)

            VStack(spacing: 6) {
                Text("Choose Your Language")
                    .font(.title2.weight(.semibold))
                Text("You can change this later in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ], spacing: 8) {
                    ForEach(AppLanguage.allCases) { language in
                        Button {
                            state.appLanguage = language
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: state.appLanguage == language
                                      ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(state.appLanguage == language ? Color.accentColor : .secondary)
                                Text(language.title)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(
                            state.appLanguage == language
                                ? Color.accentColor.opacity(0.12)
                                : Color.secondary.opacity(0.06),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                    }
                }
            }
            .frame(height: 250)

            HStack {
                if !firstRun {
                    Button("Cancel") { state.showingLanguageChooser = false }
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button(firstRun ? "Continue" : "Done") {
                    state.confirmLanguageSelection()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 540)
        .environment(\.locale, state.appLanguage.locale)
        .interactiveDismissDisabled(firstRun)
    }
}
