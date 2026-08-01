import SwiftUI
import PreferansEngine
#if canImport(UIKit)
import UIKit
#endif

/// Single home for admin/user preferences. Game-config items (seat count,
/// roster, bot speed) live in the lobby because they're per-table; this
/// screen only collects things that persist across launches.
public struct SettingsScreen: View {
    @AppStorage(SettingsKeys.revealAllHands) private var revealAllHands = false
    @AppStorage(SettingsKeys.appLanguage) private var appLanguageRaw: String = AppLanguage.default.rawValue
    @AppStorage(SettingsKeys.cardSuitDisplayOrder) private var cardSuitDisplayOrderRaw: String = CardSuitDisplayOrder.default.rawValue
    @AppStorage(SettingsKeys.trackingPermissionRequested) private var trackingPermissionRequested = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var showRelaunchPrompt = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingAccount = false
    @State private var accountDeletionError: String?
    @State private var accountStatusText = Self.accountStatusText()
    @State private var trackingStatusText = TrackingPermissionCenter.statusText
    @State private var canRequestTrackingPermission = TrackingPermissionCenter.canRequestPermission

    private let onDeleteOnlineAccount: (@MainActor () async throws -> Void)?

    public init(
        onDeleteOnlineAccount: (@MainActor () async throws -> Void)? = nil
    ) {
        self.onDeleteOnlineAccount = onDeleteOnlineAccount
    }

    public var body: some View {
        NavigationStack {
            Form {
                accountSection
                privacySection
                languageSection
                tableSection
                #if DEBUG
                Section {
                    Toggle("Reveal all hands", isOn: $revealAllHands)
                } header: {
                    Text("Admin")
                } footer: {
                    Text("Renders every seat's cards face-up. For hot-seat review and screenshot recipes — leave off for normal play.")
                        .font(.footnote)
                }
                #endif
                Section("About") {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Restart required", isPresented: $showRelaunchPrompt) {
                Button("Done", role: .cancel) {}
            } message: {
                Text("Language will switch on next launch.")
            }
            .alert(
                "settings.account.delete.confirmation.title",
                isPresented: $showDeleteAccountConfirm
            ) {
                Button("Delete online account", role: .destructive) {
                    Task { await deleteOnlineAccount() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently deletes the server account and game library, removes your identity from rooms, and clears this device. Active games you joined will be abandoned. You can register again later.")
            }
            .alert("Account deletion failed", isPresented: accountDeletionErrorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(accountDeletionError ?? "")
            }
            .onAppear {
                refreshAccountStatus()
                refreshTrackingStatus()
            }
            .accessibilityIdentifier(UIIdentifiers.screenSettings)
        }
    }

    private var accountSection: some View {
        Section {
            LabeledContent("Online account", value: accountStatusText)
            Button(role: .destructive) {
                showDeleteAccountConfirm = true
            } label: {
                if isDeletingAccount {
                    HStack {
                        ProgressView()
                        Text("Deleting online account…")
                    }
                } else {
                    Label("Delete online account", systemImage: "trash")
                }
            }
            .disabled(onDeleteOnlineAccount == nil || isDeletingAccount)
            .accessibilityIdentifier(UIIdentifiers.onlineDeleteAccount)

            if usesCollapsibleExplanations {
                DisclosureGroup {
                    Text(accountExplanation)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("What account deletion removes", systemImage: "info.circle")
                }
            }
        } header: {
            Text("Account")
        } footer: {
            if !usesCollapsibleExplanations {
                Text(accountExplanation)
                .font(.footnote)
            }
        }
    }

    private var privacySection: some View {
        Section {
            LabeledContent("Tracking permission", value: trackingStatusText)
            Button {
                Task { await requestTrackingPermission() }
            } label: {
                Label("Request tracking permission", systemImage: "hand.raised")
            }
            .disabled(!canRequestTrackingPermission)
            .accessibilityIdentifier(UIIdentifiers.trackingPermissionRequest)

            #if canImport(UIKit)
            if !canRequestTrackingPermission {
                Button {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                } label: {
                    Label("Open Privacy Settings", systemImage: "gear")
                }
            }
            #endif

            if usesCollapsibleExplanations {
                DisclosureGroup {
                    Text(privacyExplanation)
                        .foregroundStyle(.secondary)
                } label: {
                    Label("Why this permission is needed", systemImage: "info.circle")
                }
            }
        } header: {
            Text("Privacy")
        } footer: {
            if !usesCollapsibleExplanations {
                Text(privacyExplanation)
                    .font(.footnote)
            }
        }
    }

    /// Large-content users should encounter the controls first rather than
    /// having to scroll through several screens of secondary legal copy. The
    /// explanations remain available at the requested text size in explicit
    /// disclosure rows; normal content sizes retain the familiar form footer.
    private var usesCollapsibleExplanations: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private var accountExplanation: String {
        if onDeleteOnlineAccount == nil {
            return String(localized: "Return to the lobby before deleting the online account.")
        }
        return String(localized: "Permanently deletes the server account, revokes its sessions and room credentials, and clears local account data. Shared game results retain only an anonymized seat.")
    }

    private var privacyExplanation: String {
        String(localized: "If tracking is enabled in App Store privacy labels, iOS requires this permission before the app can access the advertising identifier or track activity across apps and websites.")
    }

    private var tableSection: some View {
        Section {
            Picker("Suit order", selection: $cardSuitDisplayOrderRaw) {
                ForEach(CardSuitDisplayOrder.allCases) { order in
                    Text(order.displayName).tag(order.rawValue)
                }
            }
        } header: {
            Text("Table")
        } footer: {
            Text("Controls the visual order of face-up cards in hands.")
                .font(.footnote)
        }
    }

    private var languageSection: some View {
        Section {
            Picker("Language", selection: $appLanguageRaw) {
                ForEach(AppLanguage.allCases) { lang in
                    Text(lang.displayName).tag(lang.rawValue)
                }
            }
            .onChange(of: appLanguageRaw) { _, newValue in
                guard let lang = AppLanguage(rawValue: newValue) else { return }
                AppLanguage.apply(lang)
                showRelaunchPrompt = true
            }
            .accessibilityIdentifier(UIIdentifiers.settingsLanguagePicker)
        } header: {
            Text("Language")
        } footer: {
            Text("Applies after restarting the app.")
                .font(.footnote)
        }
    }

    private var appVersion: String {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private func requestTrackingPermission() async {
        trackingPermissionRequested = true
        await TrackingPermissionCenter.requestPermission()
        refreshTrackingStatus()
    }

    private func refreshTrackingStatus() {
        trackingStatusText = TrackingPermissionCenter.statusText
        canRequestTrackingPermission = TrackingPermissionCenter.canRequestPermission
    }

    private func refreshAccountStatus() {
        accountStatusText = Self.accountStatusText()
    }

    private var accountDeletionErrorBinding: Binding<Bool> {
        Binding(
            get: { accountDeletionError != nil },
            set: { if !$0 { accountDeletionError = nil } }
        )
    }

    private func deleteOnlineAccount() async {
        guard let onDeleteOnlineAccount else { return }
        isDeletingAccount = true
        accountDeletionError = nil
        do {
            try await onDeleteOnlineAccount()
            refreshAccountStatus()
        } catch {
            accountDeletionError = error.localizedDescription
        }
        isDeletingAccount = false
    }

    private static func accountStatusText() -> String {
        if let data = UserDefaults.standard.data(forKey: SettingsKeys.onlineRegisteredAccount),
           let account = try? PreferansJSONCoder.decoder.decode(RegisteredOnlineAccount.self, from: data),
           account.schemaVersion == AppIdentifiers.onlineAccountSchemaVersion,
           OnlineAccountSessionStore.token() != nil {
            return account.provider == .apple
                ? String(localized: "Signed in with Apple")
                : String(localized: "Guest account registered")
        }
        if let name = UserDefaults.standard.string(forKey: SettingsKeys.onlineDisplayName),
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return String(localized: "Display name saved")
        }
        return String(localized: "No saved account")
    }

}
