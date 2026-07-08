import SwiftUI
import PreferansEngine

// MARK: - Convention legend sheet

/// Tap target on the lobby hero's house-name tagline. Spells out the
/// mapping from our private rename (Одеса / Wien / Θεσσαλονίκη / Крути)
/// to the names a wider Preferans audience would recognize
/// (Sochi / Leningrad / Rostov / Stalingrad). The hover/VoiceOver hints
/// on the tagline pills cover the same ground in one line; this sheet is
/// the iPhone fallback for devices without pointer hover.
struct ConventionLegendSheet: View {
    @Environment(\.dismiss) private var dismiss

    private struct Entry: Identifiable {
        let id: String
        let house: String
        let standard: LocalizedStringKey
        let tradition: LocalizedStringKey
        let summary: LocalizedStringKey
    }

    private let entries: [Entry] = [
        Entry(id: "odesa",
              house: "Одеса",
              standard: "convention.odesa.standard",
              tradition: "convention.odesa.tradition",
              summary: "convention.odesa.summary"),
        Entry(id: "wien",
              house: "Wien",
              standard: "convention.wien.standard",
              tradition: "convention.wien.tradition",
              summary: "convention.wien.summary"),
        Entry(id: "thessaloniki",
              house: "Θεσσαλονίκη",
              standard: "convention.thessaloniki.standard",
              tradition: "convention.thessaloniki.tradition",
              summary: "convention.thessaloniki.summary"),
        Entry(id: "kruty",
              house: "Крути",
              standard: "convention.kruty.standard",
              tradition: "convention.kruty.tradition",
              summary: "convention.kruty.summary")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("convention.legend.intro")
                        .font(.callout)
                        .foregroundStyle(TableTheme.inkCreamSoft)

                    VStack(spacing: 10) {
                        ForEach(entries) { entry in
                            entryCard(entry)
                        }
                    }

                    Text("convention.legend.outro")
                        .font(.footnote)
                        .foregroundStyle(TableTheme.inkCreamDim)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .feltBackground()
            .navigationTitle(Text("convention.legend.title"))
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { dismiss() }) {
                        Text("Done").foregroundStyle(TableTheme.goldBright)
                    }
                }
            }
        }
        .accessibilityIdentifier(UIIdentifiers.conventionLegendSheet)
    }

    private func entryCard(_ entry: Entry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: entry.house)
                    .font(.title3.bold())
                    .foregroundStyle(TableTheme.goldBright)
                Text("convention.legend.replaces")
                    .font(.caption2.weight(.semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(TableTheme.inkCreamDim)
                Text(entry.standard)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(TableTheme.inkCream)
                Spacer(minLength: 0)
                Text(entry.tradition)
                    .font(.caption2)
                    .foregroundStyle(TableTheme.inkCreamSoft)
            }
            Text(entry.summary)
                .font(.footnote)
                .foregroundStyle(TableTheme.inkCream)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(TableTheme.gold.opacity(0.22), lineWidth: 0.5)
        )
    }
}
