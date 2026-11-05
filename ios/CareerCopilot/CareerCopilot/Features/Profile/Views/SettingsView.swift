import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Backend") {
                    TextField("Backend URL", text: $model.baseURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .disabled(model.profile != nil)
                    Text("Use HTTPS, or localhost for simulator development.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let profile = model.profile {
                    Section("Account") {
                        Text(profile.email)
                        Button("Link Google account") { Task { await model.googleSignIn(link: true) } }
                            .disabled(model.isLoading)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
            .alert("Account linked", isPresented: Binding(
                get: { model.notice != nil },
                set: { if !$0 { model.notice = nil } }
            )) {
                Button("OK", role: .cancel) { model.notice = nil }
            } message: {
                Text(model.notice ?? "")
            }
            .alert("Unable to link account", isPresented: Binding(
                get: { model.message != nil },
                set: { if !$0 { model.message = nil } }
            )) {
                Button("OK", role: .cancel) { model.message = nil }
            } message: {
                Text(model.message ?? "")
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
}

#Preview("Settings") {
    let model = AppViewModel()
    model.profile = Profile(email: "alex@example.com")
    return SettingsView(model: model)
}
