import SwiftUI

/// Lets you point the app at a different backend (e.g. your Mac's LAN IP when
/// running on a physical iPhone).
struct SettingsView: View {
    var onSave: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var urlText: String =
        UserDefaults.standard.string(forKey: AppConfig.streamURLKey) ?? AppConfig.defaultStreamURL
    @State private var tokenText: String =
        UserDefaults.standard.string(forKey: AppConfig.streamTokenKey) ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend stream URL") {
                    TextField("ws://192.168.1.20:8080/stream", text: $urlText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section("Access token") {
                    SecureField("Bearer token", text: $tokenText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Required by the cloud backend. Get it with `terraform output -raw stream_token`. Leave empty for a local backend with no token.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Text("On a physical iPhone, use your Mac's LAN IP instead of localhost. Find it with `ipconfig getifaddr en0` in Terminal.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let token = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
                        UserDefaults.standard.set(token, forKey: AppConfig.streamTokenKey)
                        if let url = URL(string: trimmed), !trimmed.isEmpty {
                            UserDefaults.standard.set(trimmed, forKey: AppConfig.streamURLKey)
                            onSave(url)
                        }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
