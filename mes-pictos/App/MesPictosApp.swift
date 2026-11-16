import SwiftUI
import SwiftData

@main
struct MesPictosApp: App {
    private let container: ModelContainer
    @Environment(\.scenePhase) private var scenePhase

    init() {
        container = Persistence.makeContainer()
        SpeechService.shared.configureSession()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: SpeechService.shared.appDidBecomeActive()
            case .background: SpeechService.shared.appDidEnterBackground()
            default: break
            }
        }
    }
}

struct RootView: View {
    @AppStorage(SettingsKey.onboardingDone) private var onboardingDone = false

    var body: some View {
        if onboardingDone {
            BoardView()
        } else {
            OnboardingView()
        }
    }
}
