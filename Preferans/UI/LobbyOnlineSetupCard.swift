import SwiftUI
import PreferansEngine
#if canImport(AuthenticationServices)
import AuthenticationServices
import CryptoKit
#endif

// MARK: - Online setup card

extension LobbyView {
    /// Online play, with its own identity, variant, and seat composition.
    /// Two intents, in reading order: a guest with an invite finds "Join a
    /// table" right under their identity, without scrolling through the
    /// host-only variant/seat configuration that follows.
    var onlineSetupCard: some View {
        VStack(spacing: 12) {
            onlineIdentitySection
            onlineJoinSection
            onlineVariantSection
            onlineCompositionSection
            onlineRoomActionsSection
            hiddenLocalTestRoomButton
        }
    }

    /// Online seat composition — the host picks how many seats and, for each
    /// non-host seat, whether it's an open invite or a bot. Entirely separate
    /// from the local `seats` roster.
    private var onlineVariantSection: some View {
        onlinePanel(title: "Variant", icon: "slider.horizontal.3") {
            variantControls
            pulkaLimitPicker
            raspasyControls
        }
    }

    /// Shared convention controls for local and online play. A convention is a
    /// rules choice, not a networking choice, so both lobby paths must seed the
    /// same engine profile and pool-closing policy.
    var variantControls: some View {
        Group {
            if !layoutPolicy.usesTabletChrome && !layoutPolicy.usesAccessibilityText {
                compactVariantGrid
            } else {
                Picker("Variant", selection: $viewModel.onlineVariant) {
                    ForEach(PreferansVariant.allCases) { variant in
                        Text(variant.title).tag(variant)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(UIIdentifiers.onlineVariantPicker)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.onlineVariant.standardName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TableTheme.inkCream)
                Text(viewModel.onlineVariant.summary)
                    .font(.caption)
                    .foregroundStyle(TableTheme.inkCreamSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// Four long convention names do not fit four equal segments on an
    /// iPhone. Two full-width rows preserve direct selection and keep every
    /// visible label readable; iPad retains the denser segmented control.
    private var compactVariantGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)],
            spacing: 8
        ) {
            ForEach(PreferansVariant.allCases) { variant in
                let selected = viewModel.onlineVariant == variant
                Button {
                    viewModel.onlineVariant = variant
                } label: {
                    Text(variant.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(selected ? TableTheme.feltDeep : TableTheme.inkCream)
                        .background(
                            selected ? TableTheme.goldBright : Color.black.opacity(0.22),
                            in: RoundedRectangle(cornerRadius: 9)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(UIIdentifiers.onlineVariantPicker).\(variant.rawValue)")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(UIIdentifiers.onlineVariantPicker)
    }

    private var onlineCompositionSection: some View {
        onlinePanel(title: "Seats", icon: "person.3.fill") {
            onlineTableSizeRow
            VStack(spacing: 8) {
                ForEach(Array(viewModel.onlineComposition.enumerated()), id: \.element.id) { index, slot in
                    onlineSeatRow(index: index, slot: slot)
                }
            }
        }
    }

    private var onlineTableSizeRow: some View {
        HStack {
            Label {
                Text("Players")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TableTheme.inkCream)
            } icon: {
                Image(systemName: "person.3.fill")
                    .foregroundStyle(TableTheme.goldBright)
            }
            Spacer()
            Picker("Players", selection: onlineTableSizeBinding) {
                Text("3").tag(3)
                Text("4").tag(4)
            }
            .pickerStyle(.segmented)
            .frame(width: 96)
            .accessibilityIdentifier(UIIdentifiers.onlineTableSizePicker)
        }
        .padding(10)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
    }

    private func onlineSeatRow(index: Int, slot: OnlineSeatSlot) -> some View {
        HStack(spacing: 10) {
            Image(systemName: seatIcon(for: slot.kind))
                .foregroundStyle(slot.kind == .you ? TableTheme.goldBright : TableTheme.gold)
                .font(.title3)
                .frame(width: 24)
            if slot.kind == .you {
                Text(verbatim: viewModel.currentOnlineDisplayName.isEmpty ? String(localized: "You") : viewModel.currentOnlineDisplayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TableTheme.inkCream)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("badge.you")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(TableTheme.feltDeep)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(TableTheme.goldBright, in: Capsule())
            } else {
                Text("Seat \(index + 1)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(TableTheme.inkCreamSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Picker("Seat \(index + 1)", selection: onlineSeatKindBinding(index)) {
                    Text("Friend").tag(OnlineSeatSlot.Kind.invite)
                    Text("Bot").tag(OnlineSeatSlot.Kind.bot)
                }
                .pickerStyle(.segmented)
                .frame(width: 130)
                .accessibilityIdentifier(UIIdentifiers.onlineSeatKindPicker(index: index))
            }
        }
        .padding(10)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityIdentifier(UIIdentifiers.onlineSeatRow(index: index))
    }

    private func seatIcon(for kind: OnlineSeatSlot.Kind) -> String {
        switch kind {
        case .you:    return "person.crop.circle.fill"
        case .invite: return "person.badge.plus"
        case .bot:    return "cpu"
        }
    }

    private var onlineTableSizeBinding: Binding<Int> {
        Binding(
            get: { viewModel.onlineComposition.count },
            set: { viewModel.setOnlineTableSize($0) }
        )
    }

    private func onlineSeatKindBinding(_ index: Int) -> Binding<OnlineSeatSlot.Kind> {
        Binding(
            get: {
                viewModel.onlineComposition.indices.contains(index)
                    ? viewModel.onlineComposition[index].kind
                    : .invite
            },
            set: { viewModel.setOnlineSeatKind($0, at: index) }
        )
    }

    /// Prominent, in-context affordance shown the moment a valid invite code is
    /// present (pasted or arrived via a `/join/<code>` link) — replacing the old
    /// behavior where the code silently dropped into the text field with no cue.
    private func readyToJoinRow(code: String) -> some View {
        Button {
            viewModel.joinCloudflareOnlineRoom()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "ticket.fill")
                    .foregroundStyle(TableTheme.goldBright)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Join table \(code)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(TableTheme.inkCream)
                    Text("Tap to take a seat")
                        .font(.caption2)
                        .foregroundStyle(TableTheme.inkCreamDim)
                }
                Spacer(minLength: 0)
                if viewModel.isOnlineRoomLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title3)
                        .foregroundStyle(TableTheme.goldBright)
                }
            }
            .padding(12)
            .background(TableTheme.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(TableTheme.gold.opacity(0.40), lineWidth: 0.75)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isOnlineRoomLoading || viewModel.onlineIdentityValidationError != nil)
        .accessibilityIdentifier(UIIdentifiers.onlineJoinRoom)
    }

    /// Online identity, decoupled from the local roster. Signed-in users see a
    /// status row; everyone else gets a name field (what opponents see) plus
    /// Sign in with Apple. Neither path ever writes into the local `seats`.
    @ViewBuilder
    private var onlineIdentitySection: some View {
        onlinePanel(title: "You", icon: "person.crop.circle.fill") {
            if viewModel.registeredOnlineAccount != nil {
                identityStatusRow(
                    icon: "person.crop.circle.badge.checkmark",
                    title: String(localized: "Signed in as \(viewModel.currentOnlineDisplayName)"),
                    trailingAction: {
                        Button {
                            viewModel.clearRegisteredOnlineAccount()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(TableTheme.inkCreamSoft)
                        .accessibilityLabel("Sign out")
                    }
                )
            } else {
                onlineNameField

                Button {
                    viewModel.registerGuestOnlineAccount()
                } label: {
                    Label("Continue as Guest", systemImage: "person.crop.circle.badge.plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(TableTheme.gold)
                .disabled(
                    viewModel.isOnlineRoomLoading ||
                    viewModel.onlineDisplayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .accessibilityIdentifier(UIIdentifiers.onlineRegisterAsGuest)

                #if canImport(AuthenticationServices)
                // Full width and 44pt tall: aligned to the same grid (and
                // minimum touch-target size) as the other lobby CTAs.
                SignInWithAppleButton(
                    .signIn,
                    onRequest: configureAppleSignIn,
                    onCompletion: handleAppleSignIn
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 44)
                .frame(maxWidth: .infinity)
                .clipShape(Capsule())
                .accessibilityIdentifier(UIIdentifiers.onlineRegisterWithApple)
                #endif
            }
            if let validation = viewModel.onlineIdentityValidationError {
                Text(validation)
                    .font(.caption)
                    .foregroundStyle(TableTheme.warningInk)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Guest path: paste/read an invite, take a seat. The prominent
    /// ready-to-join row doubles as the single join trigger — the field on
    /// its own can't be "submitted invalid", so no second button is needed.
    private var onlineJoinSection: some View {
        onlinePanel(title: "Join a table", icon: "ticket.fill") {
            if let pendingCode = viewModel.pendingJoinRoomCode {
                readyToJoinRow(code: pendingCode)
            } else if isUIAutomation {
                // Keep the join automation root alive while no code is
                // pending — same 1×1 idiom as the other hidden affordances.
                Button { viewModel.joinCloudflareOnlineRoom() } label: { Color.clear }
                    .frame(width: 1, height: 1)
                    .opacity(0.001)
                    .allowsHitTesting(true)
                    .accessibilityIdentifier(UIIdentifiers.onlineJoinRoom)
            }
            TextField(
                "Paste link or code",
                text: $viewModel.onlineJoinRoomCode,
                prompt: Text("Paste link or code")
                    .foregroundStyle(TableTheme.inkCreamDim)
            )
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            #if canImport(UIKit)
            .textInputAutocapitalization(.characters)
            #endif
            .submitLabel(.go)
            .onSubmit {
                if viewModel.pendingJoinRoomCode != nil { viewModel.joinCloudflareOnlineRoom() }
            }
            .foregroundStyle(TableTheme.inkCream)
            .padding(10)
            .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
            .accessibilityIdentifier(UIIdentifiers.onlineJoinRoomCode)
        }
    }

    /// Host path: the terminal CTA after variant + seats are set.
    private var onlineRoomActionsSection: some View {
        onlinePanel(title: "Start a table", icon: "link") {
            Button {
                viewModel.startCloudflareOnlineRoom()
            } label: {
                HStack {
                    if viewModel.isOnlineRoomLoading {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "person.3.sequence.fill")
                    }
                    Text("Create invite link")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.feltPrimary)
            .controlSize(.large)
            .disabled(
                viewModel.onlineSetupValidationError != nil
                    || viewModel.isOnlineRoomLoading
            )
            .accessibilityIdentifier(UIIdentifiers.onlineCreateRoom)

            // The field-level error in the "You" panel is the fix-it cue;
            // down here a quiet pointer explains the disabled CTA without
            // repeating the alert.
            if viewModel.onlineSetupValidationError != nil {
                Text(
                    viewModel.currentOnlineDisplayName.isEmpty
                        ? String(localized: "Add your name above to create a table.")
                        : String(localized: "Finish registration above to create a table.")
                )
                    .font(.caption2)
                    .foregroundStyle(TableTheme.inkCreamDim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var onlineNameField: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .font(.title3)
                .foregroundStyle(TableTheme.goldBright)
            TextField(
                "Your name",
                text: onlineNameBinding,
                prompt: Text("Your name").foregroundStyle(TableTheme.inkCreamDim)
            )
            .textFieldStyle(.plain)
            .autocorrectionDisabled()
            .foregroundStyle(TableTheme.inkCream)
            .accessibilityIdentifier(UIIdentifiers.onlineDisplayNameField)
        }
        .padding(10)
        .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
    }

    private var onlineNameBinding: Binding<String> {
        Binding(
            get: { viewModel.onlineDisplayName },
            set: { viewModel.setOnlineDisplayName($0) }
        )
    }

    @ViewBuilder
    private var hiddenLocalTestRoomButton: some View {
        #if DEBUG
        if isUIAutomation {
            Button { viewModel.startInMemoryOnlineRoom() } label: { Color.clear }
                .frame(width: 1, height: 1)
                .opacity(0.001)
                .allowsHitTesting(true)
                .accessibilityIdentifier(UIIdentifiers.onlineCreateTestRoom)
        }
        #endif
    }

    private func identityStatusRow<Trailing: View>(
        icon: String,
        title: String,
        @ViewBuilder trailingAction: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(TableTheme.goldBright)
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(TableTheme.inkCream)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            trailingAction()
        }
        .padding(10)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
    }

    private func identityStatusRow(icon: String, title: String) -> some View {
        identityStatusRow(icon: icon, title: title) {
            EmptyView()
        }
    }

    #if canImport(AuthenticationServices)
    private func configureAppleSignIn(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName]
        let nonce = UUID().uuidString.lowercased()
        appleSignInNonce = nonce
        request.nonce = SHA256.hash(data: Data(nonce.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                viewModel.errorText = String(localized: "Apple sign-in did not return an app account.")
                return
            }
            guard let tokenData = credential.identityToken,
                  let identityToken = String(data: tokenData, encoding: .utf8),
                  let nonce = appleSignInNonce else {
                viewModel.errorText = String(localized: "Apple sign-in did not return a verifiable identity.")
                return
            }
            viewModel.completeAppleRegistration(
                identityToken: identityToken,
                nonce: nonce,
                fullName: credential.fullName
            )
        case let .failure(error):
            if let authorizationError = error as? ASAuthorizationError,
               authorizationError.code == .canceled {
                return
            }
            viewModel.errorText = error.localizedDescription
        }
    }
    #endif
}
