import SwiftUI
import UniformTypeIdentifiers
import GoogleSignIn

@main
struct CareerCopilotApp: App {
    @AppStorage("appLanguage") private var appLanguage = "system"

    private var selectedLocale: Locale {
        appLanguage == "system" ? .current : Locale(identifier: appLanguage)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.locale, selectedLocale)
                .environment(\.layoutDirection, selectedLocale.language.characterDirection == .rightToLeft ? .rightToLeft : .leftToRight)
                .onOpenURL { url in _ = GIDSignIn.sharedInstance.handle(url) }
        }
    }
}
