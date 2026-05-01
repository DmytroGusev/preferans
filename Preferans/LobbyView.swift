import AuthenticationServices
import SwiftUI
import UIKit

struct LobbyView: View {
    @EnvironmentObject private var game: GameViewModel
    @State private var gmailEmail: String = ""
    @State private var gmailDisplayName: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                accountSection
                settingsSection
                seatsSection
                onlineSection
                statusSection
                startSection
            }
            .padding()
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preferans")
                .font(.largeTitle.bold())
            Text("Create a room, share the room code, or join with a code from a friend.")
                .foregroundStyle(.secondary)
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Account")
                .font(.headline)

            if let profile = game.onlineProfile {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.displayName)
                                .font(.headline)
                            Text(accountProviderTitle(profile.provider))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Sign Out") {
                            game.signOutOnlineProfile()
                        }
                        .buttonStyle(.bordered)
                    }

                    Text("Online room invites require a signed-in identity so other players can see who joined.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        game.handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Use Gmail for testing")
                            .font(.subheadline.weight(.semibold))

                        TextField("Gmail address", text: $gmailEmail)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()

                        TextField("Display name", text: $gmailDisplayName)
                            .textFieldStyle(.roundedBorder)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()

                        Button {
                            game.signInWithGoogleEmail(email: gmailEmail, displayName: gmailDisplayName)
                        } label: {
                            Label("Continue with Gmail", systemImage: "envelope.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(gmailEmail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .padding()
                    .background(Color.white.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button {
                        game.signInAsGuest(displayName: gmailDisplayName)
                    } label: {
                        Label("Continue as Test Guest", systemImage: "person.crop.circle.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Text("For this test build, Gmail sign-in creates a stable in-app profile from your email. It is enough to create/join online rooms and test friends gameplay.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Players", selection: $game.playerCount) {
                Text("3 Players").tag(3)
                Text("4 Players").tag(4)
            }
            .pickerStyle(.segmented)
            .onChange(of: game.playerCount) { _, _ in
                game.configurePlayers()
                game.syncActiveRoomSettings()
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Convention")
                    .font(.headline)

                Picker("Rules", selection: $game.ruleSet) {
                    ForEach(PreferansRuleSet.allCases) { rule in
                        Text(rule.title).tag(rule)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: game.ruleSet) { _, _ in
                    game.syncActiveRoomSettings()
                }

                Text(game.ruleSet.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var seatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Seats")
                .font(.headline)

            ForEach(visiblePlayerIndices, id: \.self) { index in
                HStack {
                    TextField("Player", text: $game.players[index].name)
                        .textFieldStyle(.roundedBorder)
                        .disabled(game.activeRoom?.sortedParticipants.contains(where: { $0.seat == index }) == true)

                    if game.playerCount == 4 && game.players[index].isSittingOut {
                        Text("Dealer sits out")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var onlineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Online Room")
                .font(.headline)

            if let room = game.activeRoom {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Room Code")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(room.code)
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .monospaced()
                                .textSelection(.enabled)
                            Text("Host: \(hostName(for: room))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Leave Room") {
                            game.leaveActiveRoom()
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack {
                        Button {
                            UIPasteboard.general.string = room.code
                            game.onlineStatusMessage = "Room code \(room.code) copied."
                        } label: {
                            Label("Copy Code", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.borderedProminent)

                        ShareLink(item: "Join my Preferans room with code \(room.code)") {
                            Label("Share Code", systemImage: "square.and.arrow.up")
                        }

                        if game.isHostOfActiveRoom {
                            Text("Host can still change seats/rules above.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Participants")
                            .font(.subheadline.weight(.semibold))

                        ForEach(room.sortedParticipants) { participant in
                            HStack {
                                Text(seatTitle(participant.seat))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 56, alignment: .leading)
                                Text(participant.displayName)
                                    .font(.body.weight(.medium))
                                if participant.isHost {
                                    Text("Host")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(red: 0.75, green: 0.61, blue: 0.24).opacity(0.18))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    Text("Friends can join by entering this code manually. The invite URL is optional and becomes one-tap once universal links are hosted.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Button("Create Online Room") {
                        game.createInvite()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!game.canCreateOnlineRoom)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Join a Friend")
                            .font(.subheadline.weight(.semibold))

                        HStack(spacing: 10) {
                            TextField("Room code or invite URL", text: $game.joinLinkInput)
                                .textFieldStyle(.roundedBorder)
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()

                            Button("Join") {
                                game.joinRoomFromInput()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!game.canJoinOnlineRoom)
                        }
                    }

                    Text("For the first release, room codes work without a domain. Paste a URL only if you already have one.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        if let status = game.onlineStatusMessage ?? game.multiplayerSyncStatus {
            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var startSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(game.activeRoom == nil ? "Start Local Hand" : "Start Online Hand") {
                game.startGame()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!game.canStartHand)

            Text(game.activeRoom == nil ? "Starts a local game on this device." : "Starts the hand for the current room. Only the host can start.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var visiblePlayerIndices: [Int] {
        Array(game.players.indices.prefix(game.playerCount))
    }

    private func hostName(for room: OnlineRoom) -> String {
        room.sortedParticipants.first(where: { $0.playerID == room.hostPlayerID })?.displayName ?? "Host"
    }

    private func seatTitle(_ seat: Int) -> String {
        "Seat \(seat + 1)"
    }

    private func accountProviderTitle(_ provider: AuthProvider) -> String {
        switch provider {
        case .apple:
            return "Signed in with Apple"
        case .google:
            return "Signed in with Gmail"
        case .guest:
            return "Test guest account"
        }
    }
}
