import SwiftUI
import GoogleSignInSwift

struct AuthenticationView: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                GradientIcon(symbol: "sparkles", colors: [CareerStyle.accent, .purple])
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your next step starts here.")
                        .font(.largeTitle.bold())
                    Text("Keep your resume ready for the opportunities ahead.")
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 16) {
                    TextField("Email", text: $model.email)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                    Divider()
                    SecureField("Password", text: $model.password)
                        .textContentType(model.isRegistering ? .newPassword : .password)
                }
                .padding(20)
                .careerCard()
                Button {
                    Task { await model.authenticate() }
                } label: {
                    HStack {
                        Spacer()
                        if model.isLoading { ProgressView() }
                        else { Text(model.isRegistering ? "Create account" : "Sign in").fontWeight(.semibold) }
                        Spacer()
                    }
                    .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isLoading || model.email.isEmpty || model.password.isEmpty)
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
