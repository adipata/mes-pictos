import SwiftUI
import SwiftData
import AVFoundation
import PictoCore

/// Parent settings. They are stored on this device only.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @AppStorage(SettingsKey.voiceIdentifier) private var voiceIdentifier = ""
    @AppStorage(SettingsKey.speechRate) private var speechRate = SettingsDefault.speechRate
    @AppStorage(SettingsKey.speechPitch) private var speechPitch = SettingsDefault.speechPitch

    @AppStorage(SettingsKey.showModeEnabled) private var showModeEnabled = SettingsDefault.showModeEnabled
    @AppStorage(SettingsKey.showDismissMode) private var dismissRaw = DismissMode.tapOutside.rawValue
    @AppStorage(SettingsKey.showAutoCloseSeconds) private var autoCloseSeconds = SettingsDefault.showAutoCloseSeconds
    @AppStorage(SettingsKey.showCelebration) private var celebration = SettingsDefault.showCelebration

    @AppStorage(SettingsKey.sentenceBarEnabled) private var sentenceBarEnabled = SettingsDefault.sentenceBarEnabled
    @AppStorage(SettingsKey.sentenceMaxWords) private var sentenceMaxWords = SettingsDefault.sentenceMaxWords
    @AppStorage(SettingsKey.sentenceClearAfterReading) private var sentenceClearAfterReading = SettingsDefault.sentenceClearAfterReading

    @AppStorage(SettingsKey.labelStyle) private var labelStyleRaw = LabelStyle.uppercase.rawValue
    @AppStorage(SettingsKey.showPageTabs) private var showPageTabs = SettingsDefault.showPageTabs
    @AppStorage(SettingsKey.tapInterval) private var tapInterval = SettingsDefault.tapInterval

    @AppStorage(SettingsKey.parentProtection) private var protectionRaw = ParentProtection.gestureOnly.rawValue
    @AppStorage(SettingsKey.parentCode) private var parentCode = ""
    @State private var newCode = ""

    @State private var confirmKit = false
    @State private var kitMessage: String?
    @State private var confirmResetSettings = false
    @State private var confirmEraseAll = false
    private let kit = StarterKit.load()

    private let voices = SpeechService.frenchVoices()

    var body: some View {
        NavigationStack {
            Form {
                voiceSection
                showSection
                sentenceSection
                displaySection
                protectionSection
                contentSection
                syncSection
                aboutSection
                resetSection
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }

    // MARK: Voice

    private var voiceSection: some View {
        Section {
            Picker("Voix", selection: $voiceIdentifier) {
                Text("Automatique").tag("")
                ForEach(voices, id: \.identifier) { voice in
                    Text("\(voice.name) (\(SpeechService.qualityName(voice.quality)), \(voice.language))")
                        .tag(voice.identifier)
                }
            }
            VStack(alignment: .leading) {
                Text("Vitesse")
                Slider(value: $speechRate, in: 0.3...0.6) {
                    Text("Vitesse")
                } minimumValueLabel: {
                    Image(systemName: "tortoise")
                } maximumValueLabel: {
                    Image(systemName: "hare")
                }
            }
            VStack(alignment: .leading) {
                Text("Hauteur")
                Slider(value: $speechPitch, in: 0.8...1.3)
            }
            Button {
                SpeechService.shared.speakText("Bonjour ! Je veux une pomme.")
            } label: {
                Label("Tester la voix", systemImage: "speaker.wave.2.fill")
            }
        } header: {
            Text("Voix de l'iPad")
        } footer: {
            Text("Pour une voix plus naturelle, téléchargez une voix française « améliorée » ou « premium » dans Réglages > Accessibilité > Contenu énoncé > Voix > Français. Les enregistrements de votre voix sont toujours joués en priorité.")
        }
    }

    // MARK: Show mode

    private var showSection: some View {
        Section {
            Toggle("Montrer la carte au centre", isOn: $showModeEnabled)
            if showModeEnabled {
                Picker("Pour fermer", selection: $dismissRaw) {
                    ForEach(DismissMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                Stepper(
                    autoCloseSeconds == 0 ? "Fermeture automatique : jamais" : "Fermeture automatique : \(autoCloseSeconds) s",
                    value: $autoCloseSeconds,
                    in: 0...60,
                    step: 5
                )
                Toggle("Petite animation de joie", isOn: $celebration)
            }
        } header: {
            Text("Mode montrer")
        } footer: {
            Text("Quand l'enfant choisit une carte, elle vient au centre de l'écran pour qu'il puisse la montrer à un adulte, comme une carte papier. Avec « Appui long », seul un adulte la ferme.")
        }
    }

    // MARK: Sentence bar

    private var sentenceSection: some View {
        Section {
            Toggle("Bande phrase", isOn: $sentenceBarEnabled)
            if sentenceBarEnabled {
                Stepper(
                    "Mots après le début : \(sentenceMaxWords)",
                    value: $sentenceMaxWords,
                    in: SettingsDefault.sentenceMaxWordsRange
                )
                Toggle("Effacer la phrase après lecture", isOn: $sentenceClearAfterReading)
            }
        } header: {
            Text("Bande phrase")
        } footer: {
            Text("Les cartes « début de phrase » (Je veux, Ouvre, J'ai besoin d'aide…), reconnaissables à leur bord vert, ouvrent la bande phrase au lieu d'être montrées seules : l'enfant ajoute un ou plusieurs mots de la page, puis appuie sur « Dire » pour montrer et entendre toute la phrase. Toucher une carte de la bande la retire. Une carte devient début de phrase dans son éditeur. Les mots sont lus avec leur texte prononcé : « Je veux » + « une pomme ».")
        }
    }

    // MARK: Display

    private var displaySection: some View {
        Section {
            Picker("Texte des cartes", selection: $labelStyleRaw) {
                ForEach(LabelStyle.allCases, id: \.rawValue) { style in
                    Text(style.displayName).tag(style.rawValue)
                }
            }
            Toggle("Onglets des pages visibles pour l'enfant", isOn: $showPageTabs)
            VStack(alignment: .leading) {
                Text("Ignorer les touches répétées : \(tapInterval, specifier: "%.1f") s")
                Slider(value: $tapInterval, in: 0...2, step: 0.1)
            }
        } header: {
            Text("Affichage")
        } footer: {
            Text("Sans onglets, l'enfant reste sur la page choisie en mode parent.")
        }
    }

    // MARK: Protection

    private var protectionSection: some View {
        Section {
            Picker("Protection", selection: $protectionRaw) {
                ForEach(ParentProtection.allCases) { protection in
                    Text(protection.displayName).tag(protection.rawValue)
                }
            }
            if protectionRaw == ParentProtection.code.rawValue {
                SecureField(parentCode.isEmpty ? "Nouveau code (4 à 6 chiffres)" : "Changer le code (4 à 6 chiffres)", text: $newCode)
                    .keyboardType(.numberPad)
                Button("Enregistrer le code") {
                    parentCode = newCode
                    newCode = ""
                }
                .disabled(!ParentCode.isValid(newCode))
                if parentCode.isEmpty {
                    Text("Aucun code défini : l'appui long suffit.")
                        .foregroundStyle(.secondary)
                }
            }
            if protectionRaw == ParentProtection.deviceAuth.rawValue && !DeviceAuth.isAvailable {
                Text("Face ID, Touch ID ou un code de l'appareil doit être configuré.")
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Mode parent")
        } footer: {
            Text("Le mode parent s'ouvre par un appui de 3 secondes sur le cadenas. Pour que l'enfant ne puisse pas quitter l'application, activez l'Accès guidé : Réglages > Accessibilité > Accès guidé, puis triple-cliquez sur le bouton latéral (ou principal) dans Mes Pictos.")
        }
    }

    // MARK: Sync

    private var syncSection: some View {
        Section {
            Label(
                FileManager.default.ubiquityIdentityToken == nil ? "Pas de compte iCloud sur cet appareil" : "Compte iCloud disponible",
                systemImage: FileManager.default.ubiquityIdentityToken == nil ? "icloud.slash" : "icloud"
            )
        } header: {
            Text("Synchronisation")
        } footer: {
            Text("Les pages et pictogrammes se synchronisent entre vos appareils connectés au même compte iCloud. Les réglages de cet écran restent propres à chaque appareil.")
        }
    }

    // MARK: Content

    private var contentSection: some View {
        Section {
            if let kit {
                Button {
                    confirmKit = true
                } label: {
                    Label("Ajouter le kit de démarrage (\(kit.pictogramCount) pictogrammes)", systemImage: "square.grid.3x3.fill")
                }
                .confirmationDialog(
                    "Ajouter les cartes critiques sur la barre permanente et une page par thème : \(kit.pages.map(\.title).joined(separator: ", ")) ? Les pages et cartes qui existent déjà sont conservées.",
                    isPresented: $confirmKit,
                    titleVisibility: .visible
                ) {
                    Button("Ajouter le kit") {
                        let added = PictoStore(context: context).installStarterKit(kit)
                        kitMessage = added == 0
                            ? "Le kit est déjà installé : rien à ajouter."
                            : "\(added) pictogramme\(added > 1 ? "s" : "") ajouté\(added > 1 ? "s" : "")."
                    }
                    Button("Annuler", role: .cancel) {}
                }
                .alert("Kit de démarrage", isPresented: Binding(get: { kitMessage != nil }, set: { if !$0 { kitMessage = nil } })) {
                    Button("OK") { kitMessage = nil }
                } message: {
                    Text(kitMessage ?? "")
                }
            }
        } header: {
            Text("Contenu")
        } footer: {
            Text("Le kit de démarrage contient des pictogrammes ARASAAC pour le premier vocabulaire. Pour en chercher d'autres parmi les 13 000 de la bibliothèque, ouvrez une carte en mode parent, puis « Chercher un pictogramme ARASAAC ».")
        }
    }

    // MARK: Reset

    private var resetSection: some View {
        Section {
            Button(role: .destructive) {
                confirmResetSettings = true
            } label: {
                Label("Réinitialiser les réglages de cet appareil", systemImage: "arrow.counterclockwise")
            }
            .confirmationDialog(
                "Remettre tous les réglages de cet écran à leurs valeurs par défaut ? Les pages et les cartes ne changent pas.",
                isPresented: $confirmResetSettings,
                titleVisibility: .visible
            ) {
                Button("Réinitialiser les réglages", role: .destructive) {
                    SettingsKey.resetAll()
                }
                Button("Annuler", role: .cancel) {}
            }

            Button(role: .destructive) {
                confirmEraseAll = true
            } label: {
                Label("Tout effacer et recommencer", systemImage: "trash")
            }
            .confirmationDialog(
                "Supprimer toutes les pages, toutes les cartes (photos et voix enregistrées comprises) et les réglages ? Avec iCloud, les autres appareils sont vidés aussi. Cette action est définitive.",
                isPresented: $confirmEraseAll,
                titleVisibility: .visible
            ) {
                Button("Tout effacer", role: .destructive) {
                    SpeechService.shared.stop()
                    PictoStore(context: context).deleteAllContent()
                    SettingsKey.resetAll(includingOnboarding: true)
                    dismiss()
                }
                Button("Annuler", role: .cancel) {}
            }
        } header: {
            Text("Réinitialiser")
        } footer: {
            Text("« Tout effacer » ramène l'application à son premier démarrage, où vous pourrez choisir le kit de démarrage. Pensez à faire une sauvegarde ou des captures d'écran avant.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?")
            VStack(alignment: .leading, spacing: 6) {
                Text("Pictogrammes ARASAAC")
                    .font(.headline)
                Text(ArasaacAPI.attribution)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Link("arasaac.org", destination: ArasaacAPI.website)
                    .font(.footnote)
            }
            .padding(.vertical, 4)
        } header: {
            Text("À propos et crédits")
        } footer: {
            Text("Licence CC BY-NC-SA : les pictogrammes ARASAAC ne peuvent pas être utilisés dans un but commercial, et les contenus qui les reprennent gardent la même licence.")
        }
    }
}
