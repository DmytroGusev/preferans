import SwiftUI
import PreferansEngine
#if os(iOS)
import UIKit
#endif

// MARK: - Rules and convention reference

/// An executable reference for the conventions the app can actually start.
/// Contract and raspasy numbers come from ``PreferansRulebook`` — the same
/// scoring engine used at the table — rather than a parallel list of prose
/// constants that can silently drift.
///
/// iPhone uses a compact picker followed by one scrollable explanation. iPad
/// keeps convention navigation in a persistent sidebar and the reference in a
/// wider detail column, matching the app's separate lobby compositions.
struct ConventionLegendSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selection: PreferansVariant
    private let fixedRules: PreferansRules?
    private let fixedMatch: MatchSettings?

    init(initialVariant: PreferansVariant = .odesa) {
        _selection = State(initialValue: initialVariant)
        fixedRules = nil
        fixedMatch = nil
    }

    /// In-game entry point. It explains the table's exact transported rules
    /// and match settings instead of letting the player browse into a different
    /// convention while a deal is in progress.
    init(rules: PreferansRules, match: MatchSettings) {
        let variant: PreferansVariant
        if rules.forceWhistOnSixSpades {
            variant = .kruty
        } else if rules == .leningrad {
            variant = .wien
        } else if rules == .rostov {
            variant = .thessaloniki
        } else {
            variant = .odesa
        }
        _selection = State(initialValue: variant)
        fixedRules = rules
        fixedMatch = match
    }

    private var isTablet: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .pad
        #else
        horizontalSizeClass == .regular
        #endif
    }

    private var allowsConventionSwitching: Bool {
        fixedRules == nil && fixedMatch == nil
    }

    private var rules: PreferansRules {
        fixedRules ?? selection.rules
    }

    private var match: MatchSettings {
        fixedMatch ?? MatchSettings(
            poolClosure: selection.poolClosure,
            raspasy: selection.raspasy
        )
    }

    private var examples: PreferansRulebookExamples {
        PreferansRulebook.examples(rules: rules, match: match)
    }

    var body: some View {
        NavigationStack {
            Group {
                if isTablet {
                    tabletBody
                } else {
                    phoneBody
                }
            }
            .feltBackground()
            .navigationTitle(Text("rules.reference.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { dismiss() }) {
                        Text("Done").foregroundStyle(TableTheme.goldBright)
                    }
                }
            }
            .rulesNavigationChrome()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.conventionLegendSheet)
    }

    // MARK: - Device-specific composition

    private var phoneBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if allowsConventionSwitching {
                    compactVariantPicker
                }
                detailContent
            }
            .padding(18)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
    }

    private var tabletBody: some View {
        HStack(spacing: 0) {
            tabletSidebar
                .frame(width: 220)
            Rectangle()
                .fill(TableTheme.gold.opacity(0.18))
                .frame(width: 1)
                .ignoresSafeArea(edges: .bottom)
            ScrollView {
                detailContent
                    .padding(.horizontal, 30)
                    .padding(.vertical, 24)
                    .frame(maxWidth: 840)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var compactVariantPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("rules.convention")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(TableTheme.gold)
                .textCase(.uppercase)
            Picker("rules.convention", selection: $selection) {
                ForEach(PreferansVariant.allCases) { variant in
                    Text(variant.title).tag(variant)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(UIIdentifiers.rulesVariantPicker)
        }
        .padding(14)
        .ruleCardBackground()
    }

    private var tabletSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("rules.reference.title", systemImage: "book.closed.fill")
                .font(.title3.bold())
                .foregroundStyle(TableTheme.inkCream)

            Text("rules.reference.intro")
                .font(.footnote)
                .foregroundStyle(TableTheme.inkCreamSoft)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                ForEach(PreferansVariant.allCases) { variant in
                    if allowsConventionSwitching || variant == selection {
                        sidebarButton(variant)
                    }
                }
            }

            Spacer(minLength: 0)

            Label("rules.engineBacked", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(TableTheme.gold)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(TableTheme.feltDeep.opacity(0.96))
    }

    private func sidebarButton(_ variant: PreferansVariant) -> some View {
        let selected = selection == variant
        return Button {
            selection = variant
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(variant.title)
                    .font(.headline)
                Text(variant.standardName)
                    .font(.caption)
                    .foregroundStyle(selected ? TableTheme.feltMid : TableTheme.inkCreamSoft)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .foregroundStyle(selected ? TableTheme.feltDeep : TableTheme.inkCream)
            .background(
                selected ? TableTheme.goldBright : Color.black.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .disabled(!allowsConventionSwitching)
        .accessibilityIdentifier(UIIdentifiers.rulesVariant(variant.rawValue))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    // MARK: - Shared rule detail

    private var detailContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            hero
            atAGlance
            contractTable
            misereCard
            raspasySection
            closingAndWhistSection
            Text("rules.houseVariationNote")
                .font(.caption)
                .foregroundStyle(TableTheme.inkCreamDim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Text(selection.title)
                    .font(.largeTitle.bold())
                    .foregroundStyle(TableTheme.goldBright)
                Text(selection.standardName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TableTheme.inkCreamSoft)
            }
            Text(selection.summary)
                .font(.body)
                .foregroundStyle(TableTheme.inkCream)
                .fixedSize(horizontal: false, vertical: true)
            Text("rules.reference.intro")
                .font(.footnote)
                .foregroundStyle(TableTheme.inkCreamDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .ruleCardBackground(emphasized: true)
    }

    private var atAGlance: some View {
        ruleSection(title: "rules.atAGlance", icon: "rectangle.grid.2x2.fill") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 10)], spacing: 10) {
                localizedMetricCard(
                    title: "rules.poolClosing",
                    value: match.poolClosure == .tableTotal
                        ? "rules.sharedTableTotal"
                        : "rules.perPlayer"
                )
                localizedMetricCard(
                    title: "rules.whist",
                    value: rules.whistResponsibility == .semiResponsible
                        ? "rules.semiResponsible"
                        : "rules.responsible"
                )
                localizedMetricCard(
                    title: "rules.dealerTalon",
                    value: rules.dealerTalonCompensation == .classic
                        ? "rules.dealerTalon.classic"
                        : "rules.dealerTalon.none"
                )
                .accessibilityIdentifier(UIIdentifiers.rulesDealerTalon)
                metricCard(
                    title: "rules.raspasyPrice",
                    value: examples.raspasy.map(\.trickPrice).map(String.init).joined(separator: "–")
                )
                metricCard(
                    title: "rules.exitMinimum",
                    value: examples.raspasy.map(\.minimumGameTricks).map(String.init).joined(separator: "–")
                )
            }
        }
    }

    private func localizedMetricCard(
        title: LocalizedStringKey,
        value: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(TableTheme.inkCreamSoft)
            Text(value)
                .font(.headline)
                .foregroundStyle(TableTheme.inkCream)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 11))
    }

    private func metricCard(title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption)
                .foregroundStyle(TableTheme.inkCreamSoft)
            Text(verbatim: value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(TableTheme.goldBright)
        }
        .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
        .padding(12)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 11))
    }

    private var contractTable: some View {
        ruleSection(title: "rules.contracts", icon: "suit.spade.fill") {
            Text("rules.contracts.caption")
                .font(.footnote)
                .foregroundStyle(TableTheme.inkCreamSoft)
                .fixedSize(horizontal: false, vertical: true)

            Grid(horizontalSpacing: 10, verticalSpacing: 9) {
                GridRow {
                    tableHeader("rules.contract")
                    tableHeader("rules.madePool")
                    tableHeader(usesDirectRemise ? "rules.directRemise" : "rules.undertrick")
                    tableHeader("rules.whistTrick")
                }
                Divider().gridCellColumns(4)
                ForEach(examples.contracts, id: \.tricks) { example in
                    GridRow {
                        Text(verbatim: "\(example.tricks)")
                            .font(.headline.monospacedDigit())
                        tableNumber(example.madePool)
                        tableNumber(usesDirectRemise
                            ? example.failedByOneDirectWhists
                            : example.failedByOneMountain)
                        tableNumber(example.whistPerDefenderTrick)
                    }
                }
            }
            .foregroundStyle(TableTheme.inkCream)
            .accessibilityIdentifier(UIIdentifiers.rulesContractTable)
        }
    }

    private var usesDirectRemise: Bool {
        if case .directWhistsPerDefender = rules.declarerRemisePolicy { return true }
        return false
    }

    private func tableHeader(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .font(.caption2.weight(.bold))
            .foregroundStyle(TableTheme.gold)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private func tableNumber(_ value: Int) -> some View {
        Text(verbatim: "\(value)")
            .font(.subheadline.monospacedDigit())
            .frame(maxWidth: .infinity)
    }

    private var misereCard: some View {
        ruleSection(title: "rules.misere", icon: "moon.stars.fill") {
            HStack(spacing: 12) {
                resultPill(
                    title: "rules.made",
                    value: examples.misere.madePool,
                    suffix: "rules.pool"
                )
                resultPill(
                    title: "rules.oneTrick",
                    value: examples.misere.failedOneTrickMountain,
                    suffix: "rules.mountain"
                )
            }
        }
    }

    private func resultPill(
        title: LocalizedStringKey,
        value: Int,
        suffix: LocalizedStringKey
    ) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(TableTheme.inkCreamSoft)
            HStack(spacing: 4) {
                Text(verbatim: "\(value)")
                    .font(.title3.bold().monospacedDigit())
                Text(suffix)
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(TableTheme.goldBright)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 11))
    }

    private var raspasySection: some View {
        ruleSection(title: "rules.raspasy", icon: "arrow.triangle.2.circlepath") {
            Text("rules.raspasy.caption")
                .font(.footnote)
                .foregroundStyle(TableTheme.inkCreamSoft)
                .fixedSize(horizontal: false, vertical: true)

            raspasyLayout {
                ForEach(examples.raspasy, id: \.stage) { example in
                    raspasyCard(example)
                }
            }

            Label("rules.raspasy.reset", systemImage: "arrow.uturn.backward.circle")
                .font(.footnote)
                .foregroundStyle(TableTheme.gold)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityIdentifier(UIIdentifiers.rulesRaspasyProgression)
    }

    @ViewBuilder
    private func raspasyLayout<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 200), spacing: 10)],
            alignment: .leading,
            spacing: 10,
            content: content
        )
    }

    private func raspasyCard(_ example: RaspasyRuleExample) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("rules.deal")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(TableTheme.inkCreamSoft)
                Text(verbatim: "\(example.stage)")
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(TableTheme.goldBright)
                    .accessibilityIdentifier(UIIdentifiers.rulesRaspasyStage(example.stage))
                Spacer(minLength: 0)
                Text(verbatim: "×\(example.trickPrice)")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(TableTheme.inkCream)
            }
            valueRow("rules.exitMinimum", value: "\(example.minimumGameTricks)+")
            valueRow("rules.cleanExit", value: "+\(example.cleanExitPool)")
            Divider().overlay(TableTheme.gold.opacity(0.18))
            Text("rules.zeroFourSixTricks")
                .font(.caption2)
                .foregroundStyle(TableTheme.inkCreamDim)
            valueRow(
                rules.allPassPenaltyPolicy.isDirectWhist ? "rules.directWhists" : "rules.mountain",
                value: (rules.allPassPenaltyPolicy.isDirectWhist
                    ? example.directWhistsForZeroFourSix
                    : example.mountainForZeroFourSix)
                    .map(String.init)
                    .joined(separator: " / ")
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }

    private func valueRow(_ key: LocalizedStringKey, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(key)
                .font(.caption)
                .foregroundStyle(TableTheme.inkCreamSoft)
            Spacer(minLength: 4)
            Text(verbatim: value)
                .font(.subheadline.bold().monospacedDigit())
                .foregroundStyle(TableTheme.inkCream)
        }
    }

    private var closingAndWhistSection: some View {
        ruleSection(title: "rules.tableRules", icon: "person.3.fill") {
            ruleExplanation(
                title: "rules.poolClosing",
                text: match.poolClosure == .tableTotal
                    ? "rules.wien.poolClosing"
                    : "rules.odesa.poolClosing"
            )
            ruleExplanation(
                title: "rules.whist",
                text: rules == .rostov
                    ? "rules.rostov.whist"
                    : rules.whistResponsibility == .semiResponsible
                    ? "rules.wien.whist"
                    : "rules.odesa.whist"
            )
            ruleExplanation(
                title: "rules.stalingrad",
                text: rules.forceWhistOnSixSpades
                    ? "rules.stalingrad.enabled"
                    : "rules.stalingrad.disabled"
            )
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(UIIdentifiers.rulesStalingrad)
            ruleExplanation(
                title: "rules.talon",
                text: rules.allPassTalonPolicy == .ignored
                    ? "rules.rostov.talon"
                    : "rules.talon.explanation"
            )
            ruleExplanation(
                title: "rules.dealerTalon",
                text: rules.dealerTalonCompensation == .classic
                    ? "rules.dealerTalon.explanation"
                    : "rules.dealerTalon.none.explanation"
            )
        }
    }

    private func ruleExplanation(
        title: LocalizedStringKey,
        text: LocalizedStringKey
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(TableTheme.goldBright)
            Text(text)
                .font(.footnote)
                .foregroundStyle(TableTheme.inkCream)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ruleSection<Content: View>(
        title: LocalizedStringKey,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(TableTheme.goldBright)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .ruleCardBackground()
    }
}

private extension View {
    func ruleCardBackground(emphasized: Bool = false) -> some View {
        background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(emphasized ? 0.32 : 0.24))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(
                            TableTheme.gold.opacity(emphasized ? 0.36 : 0.20),
                            lineWidth: emphasized ? 1 : 0.5
                        )
                )
        )
    }

    @ViewBuilder
    func rulesNavigationChrome() -> some View {
        #if os(iOS)
        self
            .toolbarBackground(TableTheme.feltDeep, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        #else
        self
        #endif
    }
}

private extension PreferansRules.AllPassPenaltyPolicy {
    var isDirectWhist: Bool {
        if case .directWhistsToLowest = self { return true }
        return false
    }
}
