import SwiftUI

/// Single home for admin/user preferences. Game-config items (seat count,
/// roster, bot speed) live in the lobby because they're per-table; this
/// screen only collects things that persist across launches.
public struct SettingsScreen: View {
    @AppStorage(SettingsKeys.revealAllHands) private var revealAllHands = false
    @AppStorage(SettingsKeys.appLanguage) private var appLanguageRaw: String = AppLanguage.default.rawValue
    @Environment(\.dismiss) private var dismiss

    @State private var pendingLanguage: AppLanguage?
    @State private var showRelaunchPrompt = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                languageSection
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
}
