import SwiftUI
import PreferansEngine

struct RootLaunchView: View {
    @AppStorage(SettingsKeys.firstLaunchOnboardingCompleted) private var onboardingCompleted = false

    var body: some View {
        if TestHarness.shouldShowOnboarding(completed: onboardingCompleted) {
            OnboardingView {
                onboardingCompleted = true
            }
        } else {
            LobbyView()
        }
    }
}

struct OnboardingView: View {
    @Environment(\.tableTheme) private var theme

    private let slides = OnboardingSlide.sampleSlides

    @State private var selectedIndex = 0
    @State private var didStartTrackingRequest = false
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            ThemeBackdrop().ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("Preferans")
                        .font(.system(.title2, design: theme.style.titleDesign, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)

                    Spacer()

                    Button("Skip") {
                        completeOnboarding()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.textSecondary)
                    .accessibilityIdentifier(UIIdentifiers.onboardingSkip)
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                TabView(selection: $selectedIndex) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        OnboardingSlideView(slide: slide)
                            .tag(index)
                    }
                }
                #if os(iOS)
                .tabViewStyle(.page(indexDisplayMode: .never))
                #endif

                VStack(spacing: 18) {
                    HStack(spacing: 8) {
                        ForEach(slides.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == selectedIndex ? theme.accent : theme.textMuted.opacity(0.28))
                                .frame(width: index == selectedIndex ? 28 : 8, height: 8)
                                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: selectedIndex)
                        }
                    }

                    Button {
                        if selectedIndex == slides.count - 1 {
                            completeOnboarding()
                        } else {
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                                selectedIndex += 1
                            }
                        }
                    } label: {
                        Text(selectedIndex == slides.count - 1 ? "Start playing" : "Continue")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(theme.onAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(
                                Capsule()
                                    .fill(theme.accent)
                                    .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
                            )
                    }
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier(UIIdentifiers.onboardingContinue)

                    Text("The iOS tracking permission may appear during first launch. You can continue even if you decline.")
                        .font(.caption.weight(.medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(theme.textMuted)
                        .padding(.horizontal, 28)
                        .padding(.bottom, 14)
                }
            }
        }
        .accessibilityIdentifier(UIIdentifiers.screenOnboarding)
        .task {
            await requestTrackingAfterLaunchSettles()
        }
    }

    private func requestTrackingAfterLaunchSettles() async {
        guard !didStartTrackingRequest else { return }
        didStartTrackingRequest = true
        try? await Task.sleep(nanoseconds: 1_400_000_000)
        guard !Task.isCancelled else { return }
        await TrackingPermissionCenter.requestPermissionIfNeeded()
    }

    private func completeOnboarding() {
        Task { @MainActor in
            await TrackingPermissionCenter.requestPermissionIfNeeded()
            onComplete()
        }
    }
}

private struct OnboardingSlide: Equatable {
    enum Illustration: Equatable {
        case cards
        case table
        case invite
        case scoring
    }

    let title: String
    let subtitle: String
    let illustration: Illustration

    static let sampleSlides: [OnboardingSlide] = [
        .init(
            title: "Classic Preferans, made readable",
            subtitle: "Large cards, clean bids, and a table layout tuned for phones and iPad.",
            illustration: .cards
        ),
        .init(
            title: "Play a full hand",
            subtitle: "Bid, take the talon, discard manually, choose whists, and finish with score calculation.",
            illustration: .table
        ),
        .init(
            title: "Invite friends by room code",
            subtitle: "Create an online room, share the code, and let friends join the same table.",
            illustration: .invite
        ),
        .init(
            title: "Track the pulka",
            subtitle: "Sochi, Leningrad, and Rostov variants are prepared with automatic settlement support.",
            illustration: .scoring
        )
    ]
}

private struct OnboardingSlideView: View {
    @Environment(\.tableTheme) private var theme

    let slide: OnboardingSlide
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var illustrationHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 210 : 330
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 8)

                    OnboardingIllustration(kind: slide.illustration)
                        .frame(maxWidth: 360)
                        .frame(height: illustrationHeight)
                        .padding(.horizontal, 24)
                        .accessibilityHidden(true)

                    VStack(spacing: 14) {
                        Text(slide.title)
                            .font(.system(.largeTitle, design: theme.style.titleDesign, weight: .bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(theme.textPrimary)

                        Text(slide.subtitle)
                            .font(.body.weight(.medium))
                            .lineSpacing(4)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(theme.textSecondary)
                            .padding(.horizontal, 8)
                    }
                    .padding(.horizontal, 26)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .scrollIndicators(.hidden)
        }
    }
}

private struct OnboardingIllustration: View {
    @Environment(\.tableTheme) private var theme

    let kind: OnboardingSlide.Illustration

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(theme.panel.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .stroke(theme.accent.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.28), radius: 28, y: 20)

            switch kind {
            case .cards:
                CardsIllustration()
            case .table:
                TableIllustration()
            case .invite:
                InviteIllustration()
            case .scoring:
                ScoringIllustration()
            }
        }
    }
}

private struct CardsIllustration: View {
    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { index in
                PremiumCard(rank: ["A", "K", "Q", "J", "10"][index], suit: ["♥", "♠", "♦", "♣", "♥"][index])
                    .frame(width: 88, height: 132)
                    .rotationEffect(.degrees(Double(index - 2) * 9))
                    .offset(x: CGFloat(index - 2) * 42, y: abs(CGFloat(index - 2)) * 12)
            }
        }
    }
}

private struct TableIllustration: View {
    @Environment(\.tableTheme) private var theme

    var body: some View {
        ZStack {
            Ellipse()
                .fill(theme.backgroundMid)
                .frame(width: 260, height: 172)
                .overlay(Ellipse().stroke(theme.accent.opacity(0.48), lineWidth: 2))

            Image(systemName: "suit.spade.fill")
                .font(.system(size: 48, weight: .black))
                .foregroundStyle(theme.accent)

            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(theme.panel)
                    .frame(width: 76, height: 34)
                    .overlay(Text(["You", "Mila", "Leo"][index]).font(.system(size: 12, weight: .bold)).foregroundStyle(theme.textPrimary))
                    .offset(x: [0, -96, 96][index], y: [92, -68, -68][index])
            }
        }
    }
}

private struct InviteIllustration: View {
    @Environment(\.tableTheme) private var theme

    var body: some View {
        VStack(spacing: 22) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(theme.panel)
                .frame(width: 230, height: 86)
                .overlay(
                    VStack(spacing: 6) {
                        Text("ROOM CODE")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(theme.textSecondary)
                        Text("5E5B83")
                            .font(.system(size: 33, weight: .heavy, design: .rounded))
                            .foregroundStyle(theme.textPrimary)
                    }
                )

            HStack(spacing: 16) {
                ForEach(["person.fill", "link", "person.2.fill"], id: \.self) { icon in
                    Circle()
                        .fill(theme.accent)
                        .frame(width: 58, height: 58)
                        .overlay(Image(systemName: icon).font(.system(size: 22, weight: .bold)).foregroundStyle(theme.textPrimary))
                }
            }
        }
    }
}

private struct ScoringIllustration: View {
    @Environment(\.tableTheme) private var theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(theme.panel)
                .frame(width: 238, height: 182)

            VStack(spacing: 16) {
                Text("PULKA")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(theme.textSecondary)

                HStack(spacing: 18) {
                    ForEach([("You", "10"), ("Mila", "6"), ("Leo", "8")], id: \.0) { player, score in
                        VStack(spacing: 8) {
                            Text(score)
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(theme.textPrimary)
                            Text(player)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }

                Capsule()
                    .fill(theme.error)
                    .frame(width: 156, height: 10)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(theme.accent)
                            .frame(width: 98, height: 10)
                    }
            }
        }
    }
}

private struct PremiumCard: View {
    @Environment(\.tableTheme) private var theme

    let rank: String
    let suit: String

    private var isRed: Bool {
        suit == "♥" || suit == "♦"
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.white)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.black.opacity(0.08), lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                VStack(spacing: 1) {
                    Text(rank)
                    Text(suit)
                }
                .font(.system(size: 15, weight: .heavy, design: theme.style.titleDesign))
                .foregroundStyle(isRed ? Color(red: 0.72, green: 0.10, blue: 0.09) : Color(red: 0.05, green: 0.07, blue: 0.07))
                .padding(9)
            }
            .overlay {
                Text(suit)
                    .font(.system(size: 34, weight: .black))
                    .foregroundStyle(isRed ? Color(red: 0.72, green: 0.10, blue: 0.09).opacity(0.92) : Color(red: 0.05, green: 0.07, blue: 0.07).opacity(0.92))
            }
            .shadow(color: .black.opacity(0.22), radius: 16, y: 10)
    }
}

#Preview {
    OnboardingView {}
}
