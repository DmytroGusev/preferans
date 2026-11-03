import SwiftUI

struct AnalyticsConsentView: View {
    @Environment(\.tableTheme) private var theme
    let onChoose: (Bool) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.largeTitle)
                        .foregroundStyle(theme.accent)
                        .accessibilityHidden(true)
                    Text("Help improve Preferans").font(.title2.bold())
                    Text("analytics.consent.explanation")
                    Text("You can play without analytics and change your choice in Settings at any time.")
                        .foregroundStyle(theme.textSecondary)
                    Link("Privacy Policy", destination: URL(string: "https://guruofcards.com/apps/preferans/privacy/")!)
                    Button { onChoose(true) } label: {
                        Text("Allow analytics").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("analytics.allow")
                    Button { onChoose(false) } label: {
                        Text("Continue without analytics").frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("analytics.decline")
                }
                .padding(26)
            }
            .foregroundStyle(theme.textPrimary)
            .feltBackground()
            .navigationTitle("Usage analytics")
            .themeNavigationChrome()
        }
        .interactiveDismissDisabled()
    }
}
