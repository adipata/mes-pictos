import SwiftUI
import PictoCore

/// What the parent picked in the ARASAAC search.
struct ArasaacPick {
    let id: Int
    let keyword: String
    let imageData: Data
}

/// Searches the whole ARASAAC library (about 13 000 pictograms with French keywords).
struct ArasaacSearchView: View {
    /// Pre-filled with the pictogram's label when there is one.
    var initialQuery: String = ""
    let onPick: (ArasaacPick) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ArasaacPictogram] = []
    @State private var searched = false
    @State private var isSearching = false
    @State private var downloadingID: Int?
    @State private var errorMessage: String?
    @State private var searchTask: Task<Void, Never>?

    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 160), spacing: 12)]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                Divider()
                content
            }
            .navigationTitle("Pictogrammes ARASAAC")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Text(ArasaacAPI.attribution)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
        .onAppear {
            guard !searched, !initialQuery.isEmpty else { return }
            query = initialQuery
            scheduleSearch(delay: 0)
        }
        .onDisappear { searchTask?.cancel() }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Chercher un mot en français (ex. : pomme)", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit { scheduleSearch(delay: 0) }
                .onChange(of: query) { _, _ in scheduleSearch(delay: 0.5) }
            if !query.isEmpty {
                Button {
                    query = ""
                    results = []
                    searched = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Effacer")
            }
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage {
            ContentUnavailableView {
                Label("Recherche impossible", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Réessayer") { scheduleSearch(delay: 0) }
            }
        } else if isSearching && results.isEmpty {
            ProgressView("Recherche…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if searched && results.isEmpty {
            ContentUnavailableView.search(text: query)
        } else if results.isEmpty {
            ContentUnavailableView {
                Label("Toute la bibliothèque ARASAAC", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("Tapez un mot pour trouver un pictogramme. Les images sont téléchargées une fois, puis fonctionnent hors ligne.")
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(results) { pictogram in
                        resultCell(pictogram)
                    }
                }
                .padding()
            }
            .overlay {
                if downloadingID != nil {
                    Color.black.opacity(0.15).ignoresSafeArea()
                    ProgressView("Téléchargement…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
    }

    private func resultCell(_ pictogram: ArasaacPictogram) -> some View {
        Button {
            pick(pictogram)
        } label: {
            VStack(spacing: 6) {
                AsyncImage(url: ArasaacAPI.imageURL(id: pictogram.id, resolution: 300)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .failure:
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    default:
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .padding(8)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.black.opacity(0.1)))

                Text(pictogram.title)
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(.plain)
        .disabled(downloadingID != nil)
        .accessibilityLabel(pictogram.title)
    }

    // MARK: Actions

    private func scheduleSearch(delay: Double) {
        searchTask?.cancel()
        errorMessage = nil
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2 else {
            results = []
            searched = false
            isSearching = false
            return
        }
        isSearching = true
        searchTask = Task {
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled else { return }
            do {
                let found = try await ArasaacClient.shared.search(text)
                guard !Task.isCancelled else { return }
                results = found
                searched = true
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    private func pick(_ pictogram: ArasaacPictogram) {
        downloadingID = pictogram.id
        Task {
            do {
                let data = try await ArasaacClient.shared.image(id: pictogram.id)
                onPick(ArasaacPick(id: pictogram.id, keyword: pictogram.title, imageData: data))
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            downloadingID = nil
        }
    }
}
