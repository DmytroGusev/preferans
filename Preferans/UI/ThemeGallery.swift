import SwiftUI
import PreferansEngine

struct ThemeGallery: View {
    @Environment(\.tableTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage(SettingsKeys.appTheme) private var rawTheme = AppTheme.default.rawValue

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 280 : 158), spacing: 14)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Make it your table")
                        .font(.system(.title2, design: theme.style.titleDesign, weight: .bold))
                        .foregroundStyle(theme.textPrimary)
                    Text("Choose a complete look for your cards and table. Changes apply immediately.")
                        .font(.subheadline)
                        .foregroundStyle(theme.textSecondary)
                }
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(AppTheme.allCases) { style in
                        ThemeOption(style: style, isSelected: AppTheme.resolve(rawTheme) == style) {
                            rawTheme = style.rawValue
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 800)
            .frame(maxWidth: .infinity)
        }
        .feltBackground()
        .navigationTitle("Table themes")
        .themeNavigationChrome()
        .accessibilityIdentifier(UIIdentifiers.screenThemeGallery)
    }
}

private struct ThemeOption: View {
    let style: AppTheme
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        let palette = TableTheme(style)
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                ThemeTablePreview()
                    .frame(height: 146)
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(palette.onAccent, palette.accent)
                                .padding(10)
                        }
                    }
                VStack(alignment: .leading, spacing: 5) {
                    Text(style.name)
                        .font(.system(.headline, design: style.titleDesign))
                        .foregroundStyle(palette.textPrimary)
                    Text(style.subtitle)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(palette.panel)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isSelected ? palette.accent : palette.textMuted.opacity(0.25),
                                  lineWidth: isSelected ? 2.5 : 0.75)
            }
            .environment(\.tableTheme, palette)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(style.name + ", " + style.subtitle)
        .accessibilityValue(isSelected ? String(localized: "Selected") : String(localized: "Not selected"))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityIdentifier(UIIdentifiers.themeOption(style.rawValue))
    }
}

/// These are the same cards used at the table, so the preview cannot drift to
/// a different deck. Preview content is decorative; the option owns its label.
private struct ThemeTablePreview: View {
    @Environment(\.tableTheme) private var theme

    var body: some View {
        ZStack {
            ThemeBackdrop()
            Ellipse()
                .strokeBorder(theme.accent.opacity(0.24), lineWidth: 1)
                .padding(.horizontal, 14)
                .padding(.vertical, 26)
            HStack(spacing: -19) {
                CardView(card: .hidden, size: .standard)
                    .rotationEffect(.degrees(-13))
                    .offset(y: 5)
                CardView(card: .known(Card(.spades, .ace)), size: .standard)
                    .rotationEffect(.degrees(-3))
                CardView(card: .known(Card(.hearts, .king)), size: .standard)
                    .rotationEffect(.degrees(10))
                    .offset(y: 4)
            }
            .padding(.top, 8)
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    NavigationStack { ThemeGallery() }.appAppearance()
}
