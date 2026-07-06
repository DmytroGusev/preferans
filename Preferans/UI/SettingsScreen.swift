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

    @State private var pendingLanguage: AppLanguage?
    @State private var showRelaunchPrompt = false
    @State private var showDeleteAccountConfirm = false
    @State private var accountStatusText = Self.accountStatusText()
    @State private var trackingStatusText = TrackingPermissionCenter.statusText
    @State private var canRequestTrackingPermission = TrackingPermissionCenter.canRequestPermission

    public init() {}

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
                Button("Later", role: .cancel) {}
                Button("Quit") {
                    if let lang = pendingLanguage { AppLanguage.apply(lang) }
                    // The user is the one who has to relaunch — iOS apps
                    // can't relaunch themselves cleanly. Quit so the next
                    // cold start picks up the new locale.
                    exit(0)
                }
            } message: {
                Text("Language will switch on next launch.")
            }
            .confirmationDialog(
                "Delete account data?",
                isPresented: $showDeleteAccountConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete account data", role: .destructive) {
                    Self.deleteAccountData()
                    refreshAccountStatus()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the saved online identity, display name, anonymous room account, and pending room code from this device. You can create a new identity later.")
            }
            .onAppear {
                refreshAccountStatus()
                refreshTrackingStatus()
            }
        }
    }

    private var accountSection: some View {
        Section {
            LabeledContent("Online account", value: accountStatusText)
            Button(role: .destructive) {
                showDeleteAccountConfirm = true
            } label: {
                Label("Delete account data", systemImage: "trash")
            }
            .accessibilityIdentifier(UIIdentifiers.onlineDeleteAccount)
        } header: {
            Text("Account")
        } footer: {
            Text("Deletes the locally stored online identity used for invite rooms. This app does not keep a separate server-side profile database.")
                .font(.footnote)
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
        } header: {
            Text("Privacy")
        } footer: {
            Text("If tracking is enabled in App Store privacy labels, iOS requires this permission before the app can access the advertising identifier or track activity across apps and websites.")
                .font(.footnote)
        }
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
                pendingLanguage = lang
                showRelaunchPrompt = true
            }
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

    private static func accountStatusText() -> String {
        if UserDefaults.standard.data(forKey: SettingsKeys.onlineRegisteredAccount) != nil {
            return "Signed in with Apple"
        }
        if let name = UserDefaults.standard.string(forKey: SettingsKeys.onlineDisplayName),
           !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Display name saved"
        }
        if UserDefaults.standard.string(forKey: SettingsKeys.onlineAnonymousAccountID) != nil {
            return "Anonymous room account saved"
        }
        return "No saved account"
    }

    private static func deleteAccountData() {
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineRegisteredAccount)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineAnonymousAccountID)
        UserDefaults.standard.removeObject(forKey: SettingsKeys.onlineDisplayName)
    }
}
