import SwiftUI

struct RootLaunchView: View {
    @AppStorage(SettingsKeys.firstLaunchOnboardingCompleted) private var onboardingCompleted = false

    var body: some View {
        if onboardingCompleted {
            LobbyView()
        } else {
            OnboardingView {
                onboardingCompleted = true
            }
        }
    }
}

struct OnboardingView: View {
    private let slides = OnboardingSlide.sampleSlides

    @State private var selectedIndex = 0
    @State private var didStartTrackingRequest = false
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.02, green: 0.12, blue: 0.10),
                    Color(red: 0.01, green: 0.22, blue: 0.17),
                    Color(red: 0.52, green: 0.39, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Text("Preferans")
                        .font(.system(size: 28, weight: .semibold, design: .serif))
                        .foregroundStyle(.white)

                    Spacer()

                    Button("Skip") {
                        completeOnboarding()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.74))
                }
                .padding(.horizontal, 24)
                .padding(.top, 18)

                TabView(selection: $selectedIndex) {
                    ForEach(Array(slides.enumerated()), id: \.offset) { index, slide in
                        OnboardingSlideView(slide: slide)
                            .tag(index)
                    }
                }
#if os(macOS)
                .tabViewStyle(.automatic)
#else
                .tabViewStyle(.page(indexDisplayMode: .never))
#endif

                VStack(spacing: 18) {
                    HStack(spacing: 8) {
                        ForEach(slides.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == selectedIndex ? Color.white : Color.white.opacity(0.28))
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
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Color(red: 0.02, green: 0.13, blue: 0.10))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 17)
                            .background(
                                Capsule()
                                    .fill(Color(red: 0.96, green: 0.80, blue: 0.38))
                                    .shadow(color: .black.opacity(0.18), radius: 18, y: 10)
                            )
                    }
                    .padding(.horizontal, 24)

                    Text("The iOS tracking permission may appear during first launch. You can continue even if you decline.")
                        .font(.system(size: 12, weight: .medium))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white.opacity(0.62))
                        .padding(.horizontal, 28)
                        .padding(.bottom, 14)
                }
            }
        }
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
    let slide: OnboardingSlide

    var body: some View {
        VStack(spacing: 28) {
            Spacer(minLength: 8)

            OnboardingIllustration(kind: slide.illustration)
                .frame(maxWidth: 360)
                .frame(height: 330)
                .padding(.horizontal, 24)

            VStack(spacing: 14) {
                Text(slide.title)
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.8)

                Text(slide.subtitle)
                    .font(.system(size: 17, weight: .medium))
                    .lineSpacing(4)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.74))
                    .padding(.horizontal, 8)
            }
            .padding(.horizontal, 26)

            Spacer(minLength: 0)
        }
    }
}

private struct OnboardingIllustration: View {
    let kind: OnboardingSlide.Illustration

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 38, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
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
    var body: some View {
        ZStack {
            Ellipse()
                .fill(Color(red: 0.02, green: 0.26, blue: 0.20))
                .frame(width: 260, height: 172)
                .overlay(Ellipse().stroke(Color(red: 0.91, green: 0.69, blue: 0.30).opacity(0.48), lineWidth: 2))

            Image(systemName: "suit.spade.fill")
                .font(.system(size: 48, weight: .black))
                .foregroundStyle(Color(red: 0.96, green: 0.78, blue: 0.35))

            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.white.opacity(0.13))
                    .frame(width: 76, height: 34)
                    .overlay(Text(["You", "Mila", "Leo"][index]).font(.system(size: 12, weight: .bold)).foregroundStyle(.white))
                    .offset(x: [0, -96, 96][index], y: [92, -68, -68][index])
            }
        }
    }
}

private struct InviteIllustration: View {
    var body: some View {
        VStack(spacing: 22) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.white)
                .frame(width: 230, height: 86)
                .overlay(
                    VStack(spacing: 6) {
                        Text("ROOM CODE")
                            .font(.system(size: 11, weight: .black))
                            .foregroundStyle(.black.opacity(0.42))
                        Text("5E5B83")
                            .font(.system(size: 33, weight: .heavy, design: .rounded))
                            .foregroundStyle(Color(red: 0.02, green: 0.16, blue: 0.12))
                    }
                )

            HStack(spacing: 16) {
                ForEach(["person.fill", "link", "person.2.fill"], id: \.self) { icon in
                    Circle()
                        .fill(Color(red: 0.96, green: 0.80, blue: 0.38))
                        .frame(width: 58, height: 58)
                        .overlay(Image(systemName: icon).font(.system(size: 22, weight: .bold)).foregroundStyle(Color(red: 0.02, green: 0.16, blue: 0.12)))
                }
            }
        }
    }
}

private struct ScoringIllustration: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.white)
                .frame(width: 238, height: 182)

            VStack(spacing: 16) {
                Text("PULKA")
                    .font(.system(size: 15, weight: .black))
                    .foregroundStyle(.black.opacity(0.38))

                HStack(spacing: 18) {
                    ForEach([("You", "10"), ("Mila", "6"), ("Leo", "8")], id: \.0) { player, score in
                        VStack(spacing: 8) {
                            Text(score)
                                .font(.system(size: 30, weight: .heavy, design: .rounded))
                                .foregroundStyle(Color(red: 0.03, green: 0.18, blue: 0.13))
                            Text(player)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.black.opacity(0.48))
                        }
                    }
                }

                Capsule()
                    .fill(Color(red: 0.77, green: 0.18, blue: 0.15))
                    .frame(width: 156, height: 10)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(Color(red: 0.96, green: 0.80, blue: 0.38))
                            .frame(width: 98, height: 10)
                    }
            }
        }
    }
}

private struct PremiumCard: View {
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
                .font(.system(size: 15, weight: .heavy, design: .serif))
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
