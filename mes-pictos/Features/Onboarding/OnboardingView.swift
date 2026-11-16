import SwiftUI
import SwiftData

/// First launch.
struct OnboardingView: View {
    @AppStorage(SettingsKey.onboardingDone) private var onboardingDone = false
    @Environment(\.modelContext) private var context
    private let kit = StarterKit.load()

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color.accentColor)
                    .padding(.top, 40)

                Text("Bienvenue dans Mes Pictos")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 12) {
                    point("hand.tap", "L'enfant touche une carte : elle est dite à voix haute et vient au centre de l'écran pour être montrée à un adulte.")
                    point("text.bubble", "Avec « Je veux » ou « Ouvre » puis une carte, il compose une phrase, et « Dire » la montre et la lit.")
                    point("lock", "Appuyez 3 secondes sur le cadenas pour ouvrir le mode parent et créer les cartes à partir de vos photos.")
                    point("mic", "Vous pouvez enregistrer votre voix sur chaque carte.")
                    point("magnifyingglass", "Toute la bibliothèque ARASAAC (13 000 pictogrammes en français) est disponible dans l'éditeur de carte.")
                    point("icloud", "Les pages se synchronisent avec vos autres appareils connectés au même compte iCloud.")
                }
                .frame(maxWidth: 560)

                VStack(spacing: 12) {
                    if let kit {
                        Button {
                            let store = PictoStore(context: context)
                            store.seedStarterContent()
                            store.installStarterKit(kit)
                            onboardingDone = true
                        } label: {
                            Text("Commencer avec le kit de démarrage")
                                .frame(maxWidth: 420)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Text("\(kit.pictogramCount) pictogrammes ARASAAC : les actions « J'ai besoin d'aide », « Je veux » et « Ouvre » sur la barre permanente, et une page par thème : \(kit.pages.map(\.title).joined(separator: ", ")).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        PictoStore(context: context).seedStarterContent()
                        onboardingDone = true
                    } label: {
                        Text("Commencer presque vide")
                            .frame(maxWidth: 420)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Text("Deux pages : « Mes choses » avec 4 cases vides et « Cartes critiques » (non, oui, attends, fini, encore, pause), et la barre avec « J'ai besoin d'aide », « Je veux » et « Ouvre ». Le kit peut être ajouté plus tard dans les réglages.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button {
                        onboardingDone = true
                    } label: {
                        Text("Mes Pictos est déjà configuré sur un autre appareil")
                            .frame(maxWidth: 420)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Text("Vos pages arriveront par iCloud dans quelques instants.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 560)
                .padding(.top, 12)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }

    private func point(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 32)
            Text(text)
                .font(.body)
        }
    }
}
