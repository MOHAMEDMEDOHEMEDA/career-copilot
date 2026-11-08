import SwiftUI
import GoogleSignInSwift

struct AuthenticationView: View {
    @ObservedObject var model: AppViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: Field?

    private enum Field { case email, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 16 : 24) {
                GradientIcon(symbol: "sparkles")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your next step starts here.")
                        .font(dynamicTypeSize.isAccessibilitySize ? .title2.bold() : .largeTitle.bold())
                    Text("Keep your resume ready for the opportunities ahead.")
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Email").font(.subheadline.weight(.semibold)).accessibilityHidden(true)
                        TextField("Email", text: $model.email)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled()
                            .accessibilityLabel("Email address")
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Password").font(.subheadline.weight(.semibold)).accessibilityHidden(true)
                        SecureField("Password", text: $model.password)
                            .textContentType(model.isRegistering ? .newPassword : .password)
                            .accessibilityLabel("Password")
                            .focused($focusedField, equals: .password)
                    }
                }
                .padding(20)
                .careerCard()
                Button {
                    Task { await model.authenticate() }
                } label: {
                    HStack {
                        Spacer()
                        if model.isLoading { ProgressView("Signing in") }
                        else { Text(model.isRegistering ? "Create account" : "Sign in").fontWeight(.semibold) }
                        Spacer()
                    }
                    .frame(minHeight: 44)
                }
                .careerPrimaryButton()
                .disabled(model.isLoading || model.email.isEmpty || model.password.isEmpty)
                if model.canRetrySessionRestore {
                    Button("Retry session check") { Task { await model.restoreSession() } }
                        .frame(minHeight: 44)
                        .disabled(model.isLoading)
                }
                GoogleSignInButton {
                    Task { await model.googleSignIn() }
                }
                .disabled(model.isLoading)
                Button(model.isRegistering ? "Already have an account? Sign in" : "New here? Create an account") {
                    model.isRegistering.toggle()
                }
                .frame(minHeight: 44, alignment: .leading)
                .disabled(model.isLoading)
                Text("Set your backend URL in Settings before signing in.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CareerStyle.gradient.ignoresSafeArea())
    }
}

#Preview("Sign in") {
    ScreenPreview {
        AuthenticationView(model: AppViewModel())
    }
}

#Preview("Create account") {
    let model = AppViewModel()
    model.isRegistering = true
    return ScreenPreview {
        AuthenticationView(model: model)
    }
}

#Preview("Sign in · large text") {
    ScreenPreview { AuthenticationView(model: AppViewModel()) }
        .environment(\.dynamicTypeSize, .accessibility3)
}
