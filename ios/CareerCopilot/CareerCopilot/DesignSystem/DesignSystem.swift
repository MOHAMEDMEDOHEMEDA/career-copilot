import SwiftUI

enum CareerStyle {
    static let canvas = Color(red: 0.015, green: 0.035, blue: 0.07)
    static let card = Color(red: 0.08, green: 0.13, blue: 0.19)
    static let ink = Color.white
    static let accent = Color(red: 0.08, green: 0.69, blue: 0.94)
    static let muted = Color.white.opacity(0.72)
    static let coral = Color(red: 0.12, green: 0.46, blue: 0.84)
    static let gradient = LinearGradient(
        colors: [Color(red: 0.025, green: 0.14, blue: 0.21), canvas, .black],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct CareerCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(CareerStyle.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.08)))
    }
}

extension View {
    func careerCard() -> some View { modifier(CareerCard()) }
    func careerPrimaryButton() -> some View {
        self.buttonStyle(.borderedProminent).foregroundStyle(.black)
    }
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
                .background(CareerStyle.gradient.ignoresSafeArea())
                .tint(CareerStyle.accent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {} label: { Image(systemName: "gearshape") }
                            .accessibilityLabel("Settings")
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview("Design components") {
    HStack {
        GradientIcon(symbol: "sparkles")
        GradientIcon(symbol: "doc.text")
    }
    .padding()
    .careerCard()
    .padding()
    .background(CareerStyle.gradient)
    .preferredColorScheme(.dark)
}
