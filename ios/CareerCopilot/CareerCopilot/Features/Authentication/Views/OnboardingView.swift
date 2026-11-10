import SwiftUI

enum OnboardingGate {
    static func shouldPresent(hasProfile: Bool, completed: Bool, canRetryRestore: Bool) -> Bool {
        !hasProfile && !completed && !canRetryRestore
    }
}

struct OnboardingView: View {
    @Environment(\.layoutDirection) private var layoutDirection
    private struct Page: Identifiable {
        let id: Int
        let eyebrow, title, description, symbol, detailTitle, detail: String
    }

    private static let pages: [Page] = [
        Page(id: 0, eyebrow: "YOUR CAREER COMPANION", title: "Your next move\nstarts here.", description: "Bring your career tools together in one calm space.", symbol: "sparkles", detailTitle: "A little more clarity", detail: "Turn the next step into a plan you can act on."),
        Page(id: 1, eyebrow: "BUILD YOUR STORY", title: "Put your best\nwork forward.", description: "Keep your resume close and explore how it fits the roles you care about.", symbol: "doc.text.magnifyingglass", detailTitle: "Your experience, in focus", detail: "Review your resume and explore a job match when you’re ready."),
        Page(id: 2, eyebrow: "PRACTICE WITH PURPOSE", title: "Get ready for\nwhat’s next.", description: "Practice interview questions and explore career guidance at your own pace.", symbol: "person.wave.2.fill", detailTitle: "Room to practice", detail: "Write or dictate an answer, then review your feedback.")
    ]

    @State private var page: Int
    let onCreateAccount: () -> Void
    let onSignIn: () -> Void

    init(initialPage: Int = 0, onCreateAccount: @escaping () -> Void, onSignIn: @escaping () -> Void) {
        _page = State(initialValue: initialPage)
        self.onCreateAccount = onCreateAccount
        self.onSignIn = onSignIn
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 9) {
                    Image(systemName: "sparkles").foregroundStyle(CareerStyle.accent)
                        .accessibilityHidden(true)
                    Text("Career Copilot").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                }
                Spacer()
                if page > 0 {
                    Button("Back") { withAnimation(.easeInOut(duration: 0.2)) { page -= 1 } }
                        .font(.subheadline.weight(.medium)).foregroundStyle(CareerStyle.muted)
                        .frame(minWidth: 44, minHeight: 44)
                }
                Button("Skip") { onSignIn() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(CareerStyle.muted)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityHint("Continue to sign in")
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)

            let item = Self.pages[page]
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    artwork(for: item)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 14)
                    VStack(alignment: .leading, spacing: 12) {
                        Text(LocalizedStringKey(item.eyebrow)).font(.caption.weight(.semibold)).tracking(1.3).foregroundStyle(CareerStyle.accent)
                        Text(LocalizedStringKey(item.title)).font(.largeTitle.bold()).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                        Text(LocalizedStringKey(item.description)).font(.body).foregroundStyle(CareerStyle.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label(LocalizedStringKey(item.detailTitle), systemImage: "sparkle").font(.headline).foregroundStyle(.white)
                        Text(LocalizedStringKey(item.detail)).font(.subheadline).foregroundStyle(CareerStyle.muted).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .careerCard()
                }
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
            .id(page)
            .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                let direction = layoutDirection == .rightToLeft ? -value.translation.width : value.translation.width
                if direction < -60 && page < Self.pages.count - 1 { withAnimation(.easeInOut(duration: 0.2)) { page += 1 } }
                if direction > 60 && page > 0 { withAnimation(.easeInOut(duration: 0.2)) { page -= 1 } }
            })

            VStack(spacing: 14) {
                HStack(spacing: 7) {
                    ForEach(Self.pages) { item in
                        Capsule().fill(item.id == page ? CareerStyle.accent : .white.opacity(0.22))
                            .frame(width: item.id == page ? 24 : 7, height: 7)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Introduction page \(page + 1) of \(Self.pages.count)")

                Button {
                    if page == Self.pages.count - 1 { onCreateAccount() }
                    else { withAnimation(.easeInOut(duration: 0.2)) { page += 1 } }
                } label: {
                    HStack {
                        Spacer()
                        Text(LocalizedStringKey(page == Self.pages.count - 1 ? "Create account" : "Continue")).fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                    }
                    .frame(minHeight: 52)
                    .padding(.horizontal, 20)
                    .foregroundStyle(.black)
                    .background(CareerStyle.accent, in: Capsule())
                }
                .buttonStyle(.plain)
                if page == Self.pages.count - 1 {
                    Button("Already have an account? Sign in") { onSignIn() }
                        .font(.subheadline.weight(.medium)).foregroundStyle(.white)
                        .frame(minHeight: 44)
                }
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CareerStyle.gradient.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }

    private func artwork(for item: Page) -> some View {
        ZStack {
            Circle().fill(CareerStyle.accent.opacity(0.10)).frame(width: 190, height: 190).blur(radius: 18)
            Circle().stroke(CareerStyle.accent.opacity(0.18), lineWidth: 1).frame(width: 176, height: 176)
            Circle().fill(LinearGradient(colors: [CareerStyle.card, CareerStyle.accent.opacity(0.28)], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: 132, height: 132)
            Image(systemName: item.symbol).font(.system(size: 48, weight: .medium)).foregroundStyle(CareerStyle.accent)
            Image(systemName: "sparkle").font(.title3).foregroundStyle(.white.opacity(0.8)).offset(x: 82, y: -63)
        }
        .frame(height: 200)
        .accessibilityHidden(true)
    }
}

#Preview("Onboarding · welcome") {
    OnboardingView(onCreateAccount: {}, onSignIn: {})
}

#Preview("Onboarding · finish") {
    OnboardingView(initialPage: 2, onCreateAccount: {}, onSignIn: {})
}

#Preview("Onboarding · large text") {
    OnboardingView(onCreateAccount: {}, onSignIn: {}).environment(\.dynamicTypeSize, .accessibility3)
}
