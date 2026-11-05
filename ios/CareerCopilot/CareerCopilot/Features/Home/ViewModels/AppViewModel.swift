import Combine
import Foundation
import GoogleSignIn
import UIKit

@MainActor
final class AppViewModel: ObservableObject {
    @Published var baseURL: String {
        didSet { UserDefaults.standard.set(baseURL, forKey: "baseURL") }
    }
    @Published var email = ""
    @Published var password = ""
    @Published var profile: Profile?
    @Published var message: String?
    @Published var notice: String?
    @Published var isLoading = false
    @Published var isRegistering = false

    init() {
        baseURL = UserDefaults.standard.string(forKey: "baseURL") ?? "http://localhost:8000"
    }

    private func client() throws -> APIClient {
        try APIClient.configured(baseURL: baseURL)
    }

    func authenticate() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let api = try client()
            if isRegistering { try await api.register(email: email, password: password) }
            let tokens = try await api.login(email: email, password: password)
            try TokenStore.save(tokens, baseURL: api.baseURL)
            password = ""
            profile = try await api.profile()
        } catch { message = error.localizedDescription }
    }

    func googleSignIn(link: Bool = false) async {
        isLoading = true
        defer { isLoading = false }
        do {
            guard let clientID = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
                  !clientID.isEmpty,
                  let serverID = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String,
                  !serverID.isEmpty else {
                throw GoogleSignInError.notConfigured
            }
            guard let windowScene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
                let root = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                throw GoogleSignInError.noPresentationContext
            }
            var presenter = root
            while let presented = presenter.presentedViewController { presenter = presented }
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID, serverClientID: serverID)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presenter)
            let user = try await result.user.refreshTokensIfNeeded()
            guard let idToken = user.idToken?.tokenString else { throw GoogleSignInError.missingToken }
            let api = try client()
            if link {
                try await api.linkGoogle(idToken: idToken)
                notice = "Google account linked."
            } else {
                let tokens = try await api.googleLogin(idToken: idToken)
                try TokenStore.save(tokens, baseURL: api.baseURL)
                profile = try await api.profile()
            }
        } catch {
            let googleError = error as NSError
            if googleError.domain == kGIDSignInErrorDomain && googleError.code == GIDSignInError.canceled.rawValue {
                return
            }
            message = error.localizedDescription
        }
    }

    enum GoogleSignInError: LocalizedError {
        case notConfigured, noPresentationContext, missingToken
        var errorDescription: String? {
            switch self {
            case .notConfigured: "Google Sign-In is not configured yet."
            case .noPresentationContext: "Unable to open Google Sign-In."
            case .missingToken: "Google did not return an identity token."
            }
        }
    }

    func restoreSession() async {
        do {
            let api = try client()
            guard try TokenStore.load(baseURL: api.baseURL) != nil else { return }
            profile = try await api.profile()
        } catch { message = error.localizedDescription }
    }

    func signOut() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await client().logout()
            GIDSignIn.sharedInstance.signOut()
            try TokenStore.clear()
            profile = nil
        } catch { message = error.localizedDescription }
    }
}
