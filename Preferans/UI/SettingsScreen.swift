import SwiftUI

/// Single home for admin/user preferences. Game-config items (seat count,
/// roster, bot speed) live in the lobby because they're per-table; this
/// screen only collects things that persist across launches.
public struct SettingsScreen: View {
    @AppStorage(SettingsKeys.revealAllHands) private var revealAllHands = false
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
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
        }
    }

    private var appVersion: String {
        let bundle = Bundle.main
        let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}
