import SwiftUI

enum CareerStyle {
    static let canvas = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let ink = Color.primary
    static let accent = Color(red: 0.27, green: 0.39, blue: 0.90)
    static let coral = Color(red: 0.98, green: 0.46, blue: 0.40)
}

struct CareerCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(CareerStyle.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.primary.opacity(0.04)))
    }
}

extension View {
    func careerCard() -> some View { modifier(CareerCard()) }
}

struct GradientIcon: View {
    let symbol: String
    var colors: [Color] = [CareerStyle.accent, .cyan]

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 44, height: 44)
            .background(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
            .accessibilityHidden(true)
    }
}

struct ScreenPreview<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CareerStyle.canvas)
                .tint(CareerStyle.accent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {} label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Settings")
                    }
                }
        }
    }
}

#Preview("Design components") {
    HStack {
        GradientIcon(symbol: "sparkles")
        GradientIcon(symbol: "doc.text", colors: [CareerStyle.coral, .pink])
    }
    .padding()
    .careerCard()
    .padding()
    .background(CareerStyle.canvas)
}
