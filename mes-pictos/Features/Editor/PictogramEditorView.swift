import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import PictoCore

/// Creates or edits a pictogram: picture, label, spoken text and recorded voice.
struct PictogramEditorView: View {
    let request: EditorRequest

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var label = ""
    @State private var spokenText = ""
    @State private var isStarter = false
    @State private var imageData: Data?
    @State private var imageChanged = false
    /// Where the current image comes from, kept with the pictogram for the credits and exports.
    @State private var imageSource: PictogramSource = .photo
    @State private var imageSourceRef: String?
    @State private var recordingData: Data?
    @State private var recordingChanged = false
    @State private var loaded = false

    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showArasaac = false
    @State private var capturedImage: UIImage?
    @State private var cropItem: CropItem?
    @State private var recorder = VoiceRecorder()
    @State private var confirmRemove = false

    private var isNew: Bool { request.placement == nil }
    private var trimmedLabel: String { label.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedSpoken: String { spokenText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                imageSection
                textSection
                voiceSection
                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            confirmRemove = true
                        } label: {
                            Label("Retirer de la page", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "Nouveau pictogramme" : "Modifier le pictogramme")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        _ = recorder.stop()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer", action: save)
                        .disabled(trimmedLabel.isEmpty || recorder.isRecording)
                }
            }
        }
        .interactiveDismissDisabled()
        .onAppear(perform: load)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    cropItem = CropItem(image: ImageTools.downscaled(image))
                }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera, onDismiss: {
            if let image = capturedImage {
                capturedImage = nil
                cropItem = CropItem(image: ImageTools.downscaled(image))
            }
        }) {
            CameraPicker { image in
                capturedImage = image
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showArasaac) {
            ArasaacSearchView(initialQuery: trimmedLabel) { pick in
                imageData = pick.imageData
                imageChanged = true
                imageSource = .arasaac
                imageSourceRef = String(pick.id)
                if trimmedLabel.isEmpty {
                    label = pick.keyword
                }
            }
        }
        .sheet(item: $cropItem) { item in
            CropView(image: item.image) { cropped in
                imageData = ImageTools.jpegData(cropped)
                imageChanged = true
                imageSource = .photo
                imageSourceRef = nil
                cropItem = nil
            } onCancel: {
                cropItem = nil
            }
        }
        .confirmationDialog("Retirer ce pictogramme de la page ?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Retirer", role: .destructive) {
                if let placement = request.placement {
                    PictoStore(context: context).remove(placement)
                }
                dismiss()
            }
            Button("Annuler", role: .cancel) {}
        }
    }

    // MARK: Sections

    private var imageSection: some View {
        Section("Image") {
            HStack {
                Spacer()
                preview
                    .frame(width: 180, height: 180)
                Spacer()
            }
            .listRowBackground(Color.clear)

            PhotosPicker(selection: $photoItem, matching: .images) {
                Label("Choisir dans la photothèque", systemImage: "photo.on.rectangle")
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    Label("Prendre une photo", systemImage: "camera")
                }
            }
            Button {
                showArasaac = true
            } label: {
                Label("Chercher un pictogramme ARASAAC", systemImage: "magnifyingglass")
            }
        }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(12)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: 44))
                    Text("Pas d'image")
                        .font(.footnote)
                }
                .foregroundStyle(.secondary)
            }
        }
    }

    private var textSection: some View {
        Section {
            TextField("Texte affiché (ex. : pomme)", text: $label)
                .textInputAutocapitalization(.never)
            TextField("Texte prononcé, optionnel (ex. : une pomme)", text: $spokenText)
                .textInputAutocapitalization(.never)
            Button {
                SpeechService.shared.speak(
                    label: trimmedLabel,
                    spokenText: trimmedSpoken.isEmpty ? nil : trimmedSpoken,
                    recording: recordingData
                )
            } label: {
                Label("Écouter", systemImage: "speaker.wave.2.fill")
            }
            .disabled(trimmedLabel.isEmpty && recordingData == nil)
            Toggle("Début de phrase", isOn: $isStarter)
        } header: {
            Text("Texte")
        } footer: {
            Text("Le texte prononcé remplace le texte affiché pour la voix de l'iPad. Utile pour ajouter un article (« une pomme ») ou corriger la prononciation d'un prénom. Un début de phrase (Je veux, Ouvre…) a un bord vert et ouvre la bande phrase au lieu d'être montré seul.")
        }
    }

    private var voiceSection: some View {
        Section {
            if recorder.isRecording {
                Button(role: .destructive) {
                    if let data = recorder.stop() {
                        recordingData = data
                        recordingChanged = true
                    }
                } label: {
                    Label("Arrêter l'enregistrement", systemImage: "stop.circle.fill")
                }
            } else {
                Button {
                    Task { await recorder.start() }
                } label: {
                    Label(recordingData == nil ? "Enregistrer ma voix" : "Réenregistrer", systemImage: "mic.circle.fill")
                }
            }

            if let recordingData, !recorder.isRecording {
                Button {
                    SpeechService.shared.play(recordingData)
                } label: {
                    Label("Écouter l'enregistrement", systemImage: "play.circle.fill")
                }
                Button(role: .destructive) {
                    self.recordingData = nil
                    recordingChanged = true
                } label: {
                    Label("Supprimer l'enregistrement", systemImage: "trash")
                }
            }

            if recorder.permissionDenied {
                Text("Le micro n'est pas autorisé. Autorisez-le dans Réglages > Mes Pictos.")
                    .foregroundStyle(.red)
            }
            if let error = recorder.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Voix enregistrée")
        } footer: {
            Text("S'il y a un enregistrement, il est joué à la place de la voix de l'iPad.")
        }
    }

    // MARK: Load and save

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let pictogram = request.placement?.pictogram else { return }
        label = pictogram.label
        spokenText = pictogram.spokenText ?? ""
        isStarter = pictogram.isSentenceStarter
        imageData = pictogram.imageData
        imageSource = pictogram.source
        imageSourceRef = pictogram.sourceRef
        recordingData = pictogram.recordingData
    }

    private func save() {
        let store = PictoStore(context: context)
        let spoken = trimmedSpoken.isEmpty ? nil : trimmedSpoken

        if let placement = request.placement, let pictogram = placement.pictogram {
            pictogram.label = trimmedLabel
            pictogram.spokenText = spoken
            pictogram.wordType = isStarter ? .starter : .noun
            if imageChanged {
                pictogram.imageData = imageData
                pictogram.imageVersion += 1
                pictogram.source = imageSource
                pictogram.sourceRef = imageSourceRef
                pictogram.licence = imageSource == .arasaac ? ArasaacAPI.licence : nil
            }
            if recordingChanged {
                pictogram.recordingData = recordingData
            }
            store.save()
        } else {
            let placement = store.createPictogram(
                label: trimmedLabel,
                spokenText: spoken,
                imageData: imageData,
                recordingData: recordingData,
                source: imageSource,
                sourceRef: imageSourceRef,
                licence: imageSource == .arasaac ? ArasaacAPI.licence : nil,
                wordType: isStarter ? .starter : .noun,
                on: request.page,
                slot: request.slot
            )
            if placement == nil {
                // The page filled up while the editor was open (for example through iCloud sync).
                return
            }
        }
        dismiss()
    }
}

struct CropItem: Identifiable {
    let id = UUID()
    let image: UIImage
}
