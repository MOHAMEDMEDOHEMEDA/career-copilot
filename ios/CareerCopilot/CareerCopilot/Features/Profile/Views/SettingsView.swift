import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppViewModel
    @Environment(\.layoutDirection) private var layoutDirection
    @AppStorage("appLanguage") private var appLanguage = "system"
    @State private var displayName = ""
    @State private var nameSaved = false
    var showsDoneButton = true

    var body: some View {
        NavigationStack {
            Form {
                Section("Language") {
                    Picker("App language", selection: $appLanguage) {
                        Text("System default").tag("system")
                        Text("English").tag("en")
                        Text("العربية").tag("ar")
                    }
                }
                .listRowBackground(CareerStyle.card)
                Section("Backend") {
                    TextField("Backend URL", text: $model.baseURL)
                        .environment(\.layoutDirection, .leftToRight)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .disabled(model.profile != nil)
                    Text("Use HTTPS, or localhost for simulator development.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .listRowBackground(CareerStyle.card)
                if let profile = model.profile {
                    Section("AI") {
                        NavigationLink("AI usage") { AIUsageView(model: model) }
                    }
                    .listRowBackground(CareerStyle.card)
                    Section("Profile") {
                        TextField("Your name", text: $displayName)
                            .textContentType(.name)
                            .submitLabel(.done)
                            .disabled(model.isLoading)
                            .onChange(of: displayName) { _, _ in nameSaved = false }
                        Button("Save name") { Task { nameSaved = await model.updateDisplayName(displayName) } }
                            .disabled(model.isLoading || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || displayName.unicodeScalars.count > 100 || displayName.trimmingCharacters(in: .whitespacesAndNewlines) == (profile.displayName ?? ""))
                        if nameSaved { Text("Name saved").foregroundStyle(.secondary) }
                        Text("This name appears in your workspace.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .listRowBackground(CareerStyle.card)
                    Section("Account") {
                        Text(profile.email)
                            .environment(\.layoutDirection, .leftToRight)
                        if model.isLoading { ProgressView("Updating account") }
                        Button("Link Google account") { Task { await model.googleSignIn(link: true) } }
                            .disabled(model.isLoading)
                        Button("Sign out", role: .destructive) { Task { await model.signOut() } }
                            .disabled(model.isLoading)
                    }
                    .listRowBackground(CareerStyle.card)
                }
            }
            // Recreate the native form when switching RTL/LTR so its hosted
            // controls do not retain a mirrored transform from the previous language.
            .id(layoutDirection)
            .scrollContentBackground(.hidden)
            .background(CareerStyle.gradient.ignoresSafeArea())
            .listRowBackground(CareerStyle.card)
            .navigationTitle("Settings")
            .onAppear { displayName = model.profile?.displayName ?? "" }
            .toolbar {
                if showsDoneButton { Button("Done") { dismiss() } }
            }
            .alert("Account linked", isPresented: Binding(
                get: { model.notice != nil },
                set: { if !$0 { model.notice = nil } }
            )) {
                Button("OK", role: .cancel) { model.notice = nil }
            } message: {
                Text(model.notice ?? "")
            }
            .alert("Unable to update account", isPresented: Binding(
                get: { model.message != nil },
                set: { if !$0 { model.message = nil } }
            )) {
                Button("OK", role: .cancel) { model.message = nil }
            } message: {
                Text(model.message ?? "")
            }
        }
        .tint(CareerStyle.accent)
        .preferredColorScheme(.dark)
    }

    @Environment(\.dismiss) private var dismiss
}

struct AIUsageView: View {
    @ObservedObject var model: AppViewModel
    @State private var summary: AIUsagePage.Summary?
    @State private var items: [AIUsagePage.Item] = []
    @State private var loading = false
    @State private var hasMore = false
    @State private var error: String?

    var body: some View {
        List {
            if let summary {
                Section("Usage summary") {
                    LabeledContent("Provider attempts", value: "\(summary.attempts)")
                    LabeledContent("Known input tokens", value: "\(summary.knownInputTokens)")
                    LabeledContent("Known output tokens", value: "\(summary.knownOutputTokens)")
                    LabeledContent("Known and estimated cost", value: summary.knownCostUSD.formatted(.currency(code: "USD").precision(.fractionLength(2...6))))
                    Text("Unknown cost: \(summary.attemptsWithUnknownCost) attempts · Unknown tokens: \(summary.attemptsWithUnknownTokens) attempts")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Totals are incomplete when costs or tokens are unknown. Estimates are not your bill; local inference excludes hardware and electricity.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Tracking starts after this feature is enabled and may miss interrupted requests.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Recent attempts") {
                    if items.isEmpty { Text("No AI usage recorded yet.") }
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.provider.capitalized).font(.headline)
                            if let name = item.model { Text(name).font(.subheadline) }
                            Text("\(item.operation.replacingOccurrences(of: "_", with: " ")) · \(item.outcome.replacingOccurrences(of: "_", with: " "))")
                                .font(.caption).foregroundStyle(.secondary)
                            if let cost = item.costUSD {
                                Text(cost.formatted(.currency(code: "USD").precision(.fractionLength(2...6))))
                                    .font(.caption)
                                if item.costBasis == "configured_estimate" { Text("Estimated from configured rates").font(.caption).foregroundStyle(.secondary) }
                                else if item.costBasis == "provider_reported" { Text("Reported by provider").font(.caption).foregroundStyle(.secondary) }
                                else if item.costBasis == "local_inference" { Text("Local inference").font(.caption).foregroundStyle(.secondary) }
                            } else { Text("Cost unknown").font(.caption) }
                        }
                    }
                    if hasMore { Button("Load more") { Task { await load(more: true) } }.disabled(loading) }
                }
            }
            if loading { ProgressView("Loading AI usage") }
            if let error {
                Section { Text(error); Button("Try again") { Task { await load() } } }
            }
        }
        .scrollContentBackground(.hidden)
        .background(CareerStyle.gradient.ignoresSafeArea())
        .navigationTitle("AI usage")
        .task { await load() }
    }

    private func load(more: Bool = false) async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await model.aiUsage(offset: more ? items.count : 0)
            summary = page.summary
            items = more ? items + page.items : page.items
            hasMore = page.items.count == page.limit
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}

#Preview("Settings") {
    let model = AppViewModel()
    model.profile = Profile(email: "alex@example.com")
    return SettingsView(model: model)
}

#Preview("Settings · Arabic") {
    let model = AppViewModel()
    model.profile = Profile(email: "alex@example.com", displayName: "أحمد")
    return SettingsView(model: model)
        .environment(\.locale, Locale(identifier: "ar"))
        .environment(\.layoutDirection, .rightToLeft)
}
