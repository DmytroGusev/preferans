import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var game: GameViewModel

    var body: some View {
#if DEBUG
        if let scene = AppStoreScreenshotScene.current {
            AppStoreScreenshotView(scene: scene)
                .statusBarHidden(true)
        } else {
            navigationContent
        }
#else
        navigationContent
#endif
    }

    private var navigationContent: some View {
        NavigationStack {
            appContent
            .navigationTitle("Preferans")
        }
    }

    @ViewBuilder
    private var appContent: some View {
        Group {
            switch game.screen {
            case .lobby:
                LobbyView()
            case .table:
                TableView()
            }
        }
    }
}

#if DEBUG
private enum AppStoreScreenshotScene: String {
    case lobby
    case invite
    case bidding
    case play
    case scoring

    static var current: AppStoreScreenshotScene? {
        guard ProcessInfo.processInfo.arguments.contains("-appStoreScreenshot") else {
            return nil
        }
        let rawValue = ProcessInfo.processInfo.environment["SCREENSHOT_SCENE"] ?? "lobby"
        return AppStoreScreenshotScene(rawValue: rawValue) ?? .lobby
    }

    var headline: String {
        switch self {
        case .lobby:
            return "Classic Preferans, built for iPhone"
        case .invite:
            return "Invite friends into your table"
        case .bidding:
            return "Bid smart and claim the talon"
        case .play:
            return "Follow suit. Trump at the right moment."
        case .scoring:
            return "See the hand unfold at a glance"
        }
    }

    var subtitle: String {
        switch self {
        case .lobby:
            return "Set up a 3 or 4 player table in seconds"
        case .invite:
            return "Share a room code and start together"
        case .bidding:
            return "Choose the contract that gives you control"
        case .play:
            return "Clear touch controls keep every trick readable"
        case .scoring:
            return "Track tricks, scores, and the current leader"
        }
    }
}

private struct AppStoreScreenshotView: View {
    let scene: AppStoreScreenshotScene

    private let gold = Color(red: 0.83, green: 0.67, blue: 0.34)
    private let felt = Color(red: 0.02, green: 0.24, blue: 0.18)
    private let deepFelt = Color(red: 0.00, green: 0.10, blue: 0.08)

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                premiumBackground

                VStack(alignment: .leading, spacing: 26) {
                    titleBlock
                        .padding(.top, 46)

                    devicePanel {
                        switch scene {
                        case .lobby:
                            lobbyScene
                        case .invite:
                            inviteScene
                        case .bidding:
                            biddingScene
                        case .play:
                            playScene
                        case .scoring:
                            scoringScene
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 34)
                .padding(.bottom, 28)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .ignoresSafeArea()
    }

    private var premiumBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.00, green: 0.09, blue: 0.07),
                    felt,
                    Color(red: 0.00, green: 0.06, blue: 0.05)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(gold.opacity(0.18))
                .frame(width: 520, height: 520)
                .blur(radius: 70)
                .offset(x: 210, y: -330)

            Circle()
                .fill(Color(red: 0.13, green: 0.55, blue: 0.42).opacity(0.22))
                .frame(width: 640, height: 640)
                .blur(radius: 80)
                .offset(x: -210, y: 620)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Preferans")
                .font(.system(size: 42, weight: .bold, design: .serif))
                .foregroundStyle(gold)

            Text(scene.headline)
                .font(.system(size: 54, weight: .black, design: .serif))
                .foregroundStyle(.white)
                .lineSpacing(-3)
                .minimumScaleFactor(0.78)
                .fixedSize(horizontal: false, vertical: true)

            Text(scene.subtitle)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func devicePanel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 9, height: 9)
                Text("Preferans")
                    .font(.system(size: 21, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
                Spacer()
                Text(sceneHeader)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(gold)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .background(Color.black.opacity(0.20))

            content()
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 1720)
        .background(
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [felt.opacity(0.98), deepFelt.opacity(0.98)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 42, style: .continuous)
                .stroke(gold.opacity(0.28), lineWidth: 2)
        )
        .shadow(color: .black.opacity(0.35), radius: 34, y: 20)
    }

    private var sceneHeader: String {
        switch scene {
        case .lobby: "Lobby"
        case .invite: "Online Room"
        case .bidding: "Bidding"
        case .play: "Play"
        case .scoring: "Score"
        }
    }

    private var lobbyScene: some View {
        VStack(alignment: .leading, spacing: 22) {
            segmentedControl(items: ["3 Players", "4 Players"], selected: 0)
            segmentedControl(items: ["Sochi", "Leningrad", "Rostov"], selected: 0)

            VStack(spacing: 12) {
                playerRow("You", detail: "Seat 1", active: true)
                playerRow("Mila", detail: "Seat 2", active: false)
                playerRow("Leo", detail: "Seat 3", active: false)
            }

            goldButton("Start Local Hand")

            Spacer()

            tablePreview(cards: sampleHand)
        }
    }

    private var inviteScene: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Room Code")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.62))

            Text("PREF-842")
                .font(.system(size: 58, weight: .black, design: .rounded))
                .monospaced()
                .foregroundStyle(.white)

            HStack(spacing: 12) {
                goldButton("Copy Code")
                secondaryButton("Share")
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Participants")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                playerRow("You", detail: "Host", active: true)
                playerRow("Mila", detail: "Joined", active: false)
                playerRow("Leo", detail: "Joined", active: false)
            }

            Spacer()

            tablePreview(cards: Array(sampleHand.prefix(6)))
        }
    }

    private var biddingScene: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                statusPill("Current bidder: Mila", active: true)
                Spacer()
                statusPill("6 ♠", active: false)
            }

            HStack(spacing: 10) {
                secondaryButton("Misere")
                secondaryButton("Pass")
                Spacer()
                contractStepper
            }

            HStack(spacing: 10) {
                suitButton("♠", selected: true)
                suitButton("♣", selected: false)
                suitButton("♦", selected: false)
                suitButton("♥", selected: false)
                suitButton("NT", selected: false)
            }

            Text("Your hand")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            PreviewHandView(cards: sampleHand)
                .frame(height: 220)

            Spacer()

            tablePreview(cards: Array(sampleHand.suffix(5)))
        }
    }

    private var playScene: some View {
        VStack(spacing: 26) {
            ZStack {
                RoundedRectangle(cornerRadius: 190, style: .continuous)
                    .stroke(gold.opacity(0.23), lineWidth: 3)
                    .frame(height: 520)

                VStack(spacing: 20) {
                    HStack(spacing: 30) {
                        PlayingCardView(card: Card(suit: .hearts, rank: .queen), scale: 0.86)
                        PlayingCardView(card: Card(suit: .spades, rank: .ace), scale: 0.94)
                        PlayingCardView(card: Card(suit: .clubs, rank: .ten), scale: 0.86)
                    }
                    Text("Trump: ♠  •  Trick 4 of 10")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }

            HStack(spacing: 12) {
                statusPill("You • turn", active: true)
                statusPill("Mila • waiting", active: false)
                statusPill("Leo • waiting", active: false)
            }

            PreviewHandView(cards: sampleHand)
                .frame(height: 250)
        }
    }

    private var scoringScene: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Hand finished")
                .font(.system(size: 31, weight: .black, design: .serif))
                .foregroundStyle(.white)

            Text("Mila made 7 ♠ with 8 tricks")
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))

            scoreRow("Mila", pool: 16, mountain: 0, whist: 34, leader: true)
            scoreRow("You", pool: 8, mountain: 2, whist: 18, leader: false)
            scoreRow("Leo", pool: 10, mountain: 4, whist: 12, leader: false)

            Spacer()

            VStack(alignment: .leading, spacing: 12) {
                Text("Round Summary")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                summaryLine("Declarer", "Mila")
                summaryLine("Contract", "7 ♠")
                summaryLine("Whist", "Light whist")
                summaryLine("Result", "+1 overtrick")
            }
            .padding(18)
            .background(Color.black.opacity(0.22))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private func segmentedControl(items: [String], selected: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                Text(item)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(index == selected ? .black : .white.opacity(0.75))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(index == selected ? gold : Color.white.opacity(0.07))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func playerRow(_ name: String, detail: String, active: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.62))
            }
            Spacer()
            Circle()
                .fill(active ? gold : Color.white.opacity(0.24))
                .frame(width: 12, height: 12)
        }
        .padding(17)
        .background(active ? gold.opacity(0.18) : Color.black.opacity(0.18))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func goldButton(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 19, weight: .black, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 20)
            .padding(.vertical, 15)
            .background(gold)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func secondaryButton(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var contractStepper: some View {
        HStack(spacing: 18) {
            Text("-")
            Text("6")
            Text("+")
        }
        .font(.system(size: 20, weight: .black, design: .rounded))
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .background(Color.black.opacity(0.24))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func suitButton(_ label: String, selected: Bool) -> some View {
        Text(label)
            .font(.system(size: label == "NT" ? 18 : 22, weight: .black, design: .serif))
            .foregroundStyle(selected ? gold : .white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.black.opacity(selected ? 0.34 : 0.18))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? gold.opacity(0.75) : Color.white.opacity(0.08), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func statusPill(_ text: String, active: Bool) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(active ? .black : .white.opacity(0.86))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(active ? gold : Color.black.opacity(0.22))
            .clipShape(Capsule())
    }

    private func tablePreview(cards: [Card]) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 160, style: .continuous)
                .stroke(gold.opacity(0.20), lineWidth: 3)

            HStack(spacing: -12) {
                ForEach(cards.prefix(6)) { card in
                    PlayingCardView(card: card, scale: 0.55)
                }
            }
        }
        .frame(height: 330)
    }

    private func scoreRow(_ name: String, pool: Int, mountain: Int, whist: Int, leader: Bool) -> some View {
        HStack {
            Text(name)
                .font(.system(size: 23, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 86, alignment: .leading)
            Spacer()
            scoreMetric("Pool", pool)
            scoreMetric("Mt", mountain)
            scoreMetric("Whist", whist)
        }
        .padding(18)
        .background(leader ? gold.opacity(0.18) : Color.black.opacity(0.20))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private func scoreMetric(_ title: String, _ value: Int) -> some View {
        VStack(spacing: 3) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
            Text("\(value)")
                .font(.system(size: 23, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: 70)
    }

    private func summaryLine(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.white.opacity(0.58))
            Spacer()
            Text(value)
                .foregroundStyle(.white)
                .fontWeight(.bold)
        }
        .font(.system(size: 19, weight: .semibold, design: .rounded))
    }

    private var sampleHand: [Card] {
        [
            Card(suit: .hearts, rank: .ace),
            Card(suit: .hearts, rank: .jack),
            Card(suit: .hearts, rank: .nine),
            Card(suit: .diamonds, rank: .king),
            Card(suit: .diamonds, rank: .jack),
            Card(suit: .diamonds, rank: .nine),
            Card(suit: .clubs, rank: .queen),
            Card(suit: .clubs, rank: .ten),
            Card(suit: .spades, rank: .jack),
            Card(suit: .spades, rank: .eight)
        ]
    }
}
#endif
