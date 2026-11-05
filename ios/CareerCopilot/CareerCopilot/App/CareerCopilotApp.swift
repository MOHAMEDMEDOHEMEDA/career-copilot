import SwiftUI
import UniformTypeIdentifiers
import GoogleSignIn

@main
struct CareerCopilotApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in _ = GIDSignIn.sharedInstance.handle(url) }
        }
    }
}
