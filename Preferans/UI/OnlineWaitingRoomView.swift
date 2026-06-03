import SwiftUI
import PreferansEngine

/// Pre-first-deal lobby for an online table. Replaces the old behavior of
/// dropping the host straight onto a bare felt with a "Deal" button: here the
/// host sees who's joined, shares the invite up front, and starts only once
/// every seat is filled by a human or a bot. Guests see the same roster and a
/// "waiting for the host" caption. Once the host starts (sequence ≥ 1) the
/// parent swaps this for the live table.
public struct OnlineWaitingRoomView: View {
    @ObservedObject public var coordinator: RoomOnlineGameCoordinator
    public var roomCode: String
    public var inviteURL: URL?
    public var onLeaveTable: () -> Void

    @State private var showLeaveConfirm = false
    @State private var isStarting = false

    public init(
        coordinator: RoomOnlineGameCoordinator,
        roomCode: String,
        inviteURL: URL? = nil,
        onLeaveTable: @escaping () -> Void
    ) {
        self.coordinator = coordinator
        self.roomCode = roomCode
        self.inviteURL = inviteURL
        self.onLeaveTable = onLeaveTable
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                invitePanel
                seatList
                if coordinator.isHost {
                    hostControls
                } else {
                    waitingCaption
                }
                if let error = coordinator.errorText {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier(UIIdentifiers.errorBanner)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .feltBackground()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.screenWaitingRoom)
        .confirmationDialog(
            "Leave this table?",
            isPresented: $showLeaveConfirm,
            titleVisibility: .visible
        ) {
            Button("Leave table", role: .destructive) { onLeaveTable() }
            Button("Stay", role: .cancel) {}
        } message: {
            Text("The table will be closed for everyone if you're the host.")
        }
        .onChange(of: coordinator.errorText) { _, newValue in
            // A failed start shouldn't leave the host stuck behind a disabled
            // button — re-enable the controls so they can retry.
            if newValue != nil { isStarting = false }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Waiting room")
                    .font(.title3.bold())
                    .foregroundStyle(TableTheme.inkCream)
                Text(coordinator.isHost
                     ? "Invite friends, then start when everyone's seated."
                     : "You're in. Hang tight for the host.")
                    .font(.caption)
                    .foregroundStyle(TableTheme.inkCreamDim)
            }
            Spacer(minLength: 0)
            Button {
                showLeaveConfirm = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(TableTheme.inkCream, Color.black.opacity(0.30))
                    .font(.title2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Leave table")
            .accessibilityIdentifier(UIIdentifiers.buttonLeaveTable)
        }
    }

    // MARK: - Invite

    private var invitePanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "number")
                    .foregroundStyle(TableTheme.goldBright)
                Text(verbatim: roomCode)
                    .font(.title2.bold().monospaced())
                    .foregroundStyle(TableTheme.inkCream)
                    .textSelection(.enabled)
                    .accessibilityLabel("Room code")
                    .accessibilityValue(roomCode)
                    .accessibilityIdentifier(UIIdentifiers.onlineRoomCode)
            }
            if let inviteURL {
                ShareLink(
                    item: inviteURL,
                    subject: Text("Join my Preferans table"),
                    message: Text("Join my Preferans table \(roomCode)")
                ) {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share invite link")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.feltPrimary)
                .controlSize(.large)
                .accessibilityIdentifier(UIIdentifiers.onlineShareInvite)

                Text("Share this link so friends can join — or read them the code.")
                    .font(.caption2)
                    .foregroundStyle(TableTheme.inkCreamDim)
                    .multilineTextAlignment(.center)
            } else {
                Text("Read the code to your friends so they can join.")
                    .font(.caption2)
                    .foregroundStyle(TableTheme.inkCreamDim)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.30))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(TableTheme.gold.opacity(0.22), lineWidth: 0.5)
        )
    }

    // MARK: - Seats

    private var seatList: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("Seats")
            ForEach(Array(coordinator.rosterSeats.enumerated()), id: \.element.id) { index, seat in
                seatRow(index: index, seat: seat)
            }
        }
    }

    private func seatRow(index: Int, seat: WaitingRoomSeat) -> some View {
        let info = occupancyInfo(seat.occupancy)
        return HStack(spacing: 10) {
            Image(systemName: info.icon)
                .foregroundStyle(info.iconColor)
                .font(.title3)
                .frame(width: 24)
            info.title
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(info.isOpen ? TableTheme.inkCreamSoft : TableTheme.inkCream)
                .frame(maxWidth: .infinity, alignment: .leading)
            occupancyPill(info)
        }
        .padding(10)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        // One combined element per seat: its identifier locates the row and its
        // accessibility value is a stable occupancy token ("you" / "human" /
        // "bot" / "open") tests can read without parsing visible copy.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(UIIdentifiers.waitingRoomSeat(index: index))
        .accessibilityValue(info.token)
    }

    private func occupancyPill(_ info: OccupancyInfo) -> some View {
        Text(info.pill)
            .font(.system(size: 9, weight: .bold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(info.pillAccent ? TableTheme.feltDeep : TableTheme.inkCreamSoft)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                info.pillAccent ? TableTheme.goldBright : Color.black.opacity(0.30),
                in: Capsule()
            )
    }

    // MARK: - Host controls / waiting caption

    private var hostControls: some View {
        VStack(spacing: 10) {
            Button {
                guard !isStarting else { return }
                isStarting = true
                coordinator.startFirstDeal()
            } label: {
                HStack {
                    Image(systemName: "play.fill")
                    Text("Start game")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.feltPrimary)
            .controlSize(.large)
            .disabled(!coordinator.canHostStart || isStarting)
            .accessibilityIdentifier(UIIdentifiers.onlineStartGame)

            if hasOpenSeat {
                Button {
                    guard !isStarting else { return }
                    isStarting = true
                    Task { await coordinator.fillOpenSeatsWithBotsAndStart() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu")
                            .foregroundStyle(TableTheme.goldBright)
                        Text("Fill empty seats with bots & start")
                            .fontWeight(.semibold)
                            .foregroundStyle(TableTheme.inkCream)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(TableTheme.inkCreamSoft)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(isStarting)
                .accessibilityIdentifier(UIIdentifiers.onlineFillWithBots)
            }

            if !coordinator.canHostStart {
                Text("Start is available once every seat is filled — invite a friend or fill the empty seats with bots.")
                    .font(.caption2)
                    .foregroundStyle(TableTheme.inkCreamDim)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var waitingCaption: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Waiting for the host to start…")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TableTheme.inkCreamSoft)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(UIIdentifiers.onlineWaitingForHost)
    }

    // MARK: - Helpers

    private var hasOpenSeat: Bool {
        coordinator.rosterSeats.contains { seat in
            if case .openWaiting = seat.occupancy { return true }
            return false
        }
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(TableTheme.gold)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private struct OccupancyInfo {
        let icon: String
        let iconColor: Color
        /// Built as `Text` (not `LocalizedStringKey`) so player names go out
        /// `verbatim` — a name colliding with a catalog key must not be
        /// translated — while the bot/open titles stay localizable.
        let title: Text
        let pill: LocalizedStringKey
        let pillAccent: Bool
        let isOpen: Bool
        let token: String
    }

    private func occupancyInfo(_ occupancy: WaitingRoomSeat.Occupancy) -> OccupancyInfo {
        switch occupancy {
        case let .you(name):
            return OccupancyInfo(
                icon: "person.crop.circle.fill",
                iconColor: TableTheme.goldBright,
                title: Text(verbatim: name),
                pill: "You",
                pillAccent: true,
                isOpen: false,
                token: "you"
            )
        case let .human(name):
            return OccupancyInfo(
                icon: "person.crop.circle.fill",
                iconColor: TableTheme.goldBright,
                title: Text(verbatim: name),
                pill: "Ready",
                pillAccent: false,
                isOpen: false,
                token: "human"
            )
        case .bot:
            return OccupancyInfo(
                icon: "cpu",
                iconColor: TableTheme.gold,
                title: Text("Bot"),
                pill: "Bot",
                pillAccent: false,
                isOpen: false,
                token: "bot"
            )
        case .openWaiting:
            return OccupancyInfo(
                icon: "hourglass",
                iconColor: TableTheme.inkCreamSoft,
                title: Text("Waiting for a friend…"),
                pill: "Open",
                pillAccent: false,
                isOpen: true,
                token: "open"
            )
        }
    }
}
