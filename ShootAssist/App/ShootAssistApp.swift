import SwiftUI

@main
struct ShootAssistApp: App {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @StateObject private var subManager = SubscriptionManager()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .preferredColorScheme(.light)
                .environmentObject(subManager)
                .onAppear { Analytics.track(Analytics.Event.appOpened) }
                .fullScreenCover(isPresented: Binding(
                    get: { !hasSeenOnboarding },
                    set: { _ in }
                )) {
                    OnboardingView(isPresented: Binding(
                        get: { !hasSeenOnboarding },
                        set: { showing in
                            if !showing { hasSeenOnboarding = true }
                        }
                    ))
                }
        }
    }
}
