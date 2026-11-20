import SwiftUI
import SwiftData
import PictoCore

/// Title, grid size and visibility of a page (or the number of slots of the permanent bar).
struct PageSettingsView: View {
    let page: Page

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var title: String
    @State private var columns: Int
    @State private var rows: Int
    @State private var isHidden: Bool
    @State private var color: PageColor
    @State private var iconPictogramID: UUID?
    @State private var message: String?

    private struct Preset: Identifiable {
        let columns: Int
        let rows: Int
        var id: Int { columns * rows }
    }

    private static let presets = [
        Preset(columns: 1, rows: 1), Preset(columns: 2, rows: 1), Preset(columns: 2, rows: 2),
        Preset(columns: 3, rows: 2), Preset(columns: 3, rows: 3), Preset(columns: 4, rows: 3),
        Preset(columns: 5, rows: 4), Preset(columns: 6, rows: 4), Preset(columns: 6, rows: 5),
        Preset(columns: 8, rows: 5), Preset(columns: 8, rows: 6), Preset(columns: 10, rows: 6),
        Preset(columns: 10, rows: 8),
    ]

    init(page: Page) {
        self.page = page
        _title = State(initialValue: page.title)
        _columns = State(initialValue: page.columns)
        _rows = State(initialValue: page.rows)
        _isHidden = State(initialValue: page.isHidden)
        _color = State(initialValue: page.color ?? .blue)
        _iconPictogramID = State(initialValue: page.iconPictogramID)
    }

    private var isBar: Bool { page.kind == .permanentBar }

    var body: some View {
        NavigationStack {
            Form {
                if !isBar {
                    Section("Titre") {
                        TextField("Titre de la page", text: $title)
                    }
                    tabSection
                }

                Section {
                    if !isBar {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack {
                                ForEach(Self.presets) { preset in
                                    Button("\(preset.columns * preset.rows)") {
                                        columns = preset.columns
                                        rows = preset.rows
                                    }
                                    .buttonStyle(.bordered)
                                    .tint(columns == preset.columns && rows == preset.rows ? Color.accentColor : Color.secondary)
                                }
                            }
                        }
                    }
                    Stepper("Colonnes : \(columns)", value: $columns, in: GridSize.columnRange)
                    if !isBar {
                        Stepper("Lignes : \(rows)", value: $rows, in: GridSize.rowRange)
                    }
                    if let message {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text(isBar ? "Nombre de cases" : "Nombre de cartes")
                } footer: {
                    Text(isBar
                         ? "\(columns) cases dans la barre."
                         : "\(columns * rows) cases. Au début, peu de grandes cartes aident l'enfant à choisir. Les cartes gardent leur place quand la grille change. Si les cartes deviennent trop petites pour l'écran, la page défile.")
                }

                if !isBar {
                    Section {
                        Toggle("Masquer cette page pour l'enfant", isOn: $isHidden)
                    } footer: {
                        Text("Une page masquée reste visible en mode parent.")
                    }
                }
            }
            .navigationTitle(isBar ? "Barre permanente" : "Réglages de la page")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK", action: apply)
                }
            }
        }
    }

    // MARK: Tab

    private var tabSection: some View {
        Section {
            HStack(spacing: 14) {
                PageIconView(pictogram: previewIcon, side: 56)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                Text(title.isEmpty ? "Sans titre" : title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(color.textColor)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(color.color))
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
                ForEach(PageColor.allCases) { candidate in
                    Button {
                        color = candidate
                    } label: {
                        Circle()
                            .fill(candidate.color)
                            .frame(width: 40, height: 40)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(color == candidate ? 0.8 : 0), lineWidth: 3))
                            .overlay {
                                if color == candidate {
                                    Image(systemName: "checkmark")
                                        .font(.headline)
                                        .foregroundStyle(candidate.textColor)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(candidate.displayName)
                    .accessibilityAddTraits(color == candidate ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)

            if !page.visibleCards.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        iconChoice(nil, label: "1re carte")
                        ForEach(page.visibleCards) { pictogram in
                            iconChoice(pictogram, label: pictogram.label)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("Onglet")
        } footer: {
            Text("La couleur et l'image aident l'enfant à reconnaître la page sans lire. Par défaut, l'onglet montre la première carte de la page.")
        }
    }

    private var previewIcon: Pictogram? {
        if let iconPictogramID, let chosen = page.visibleCards.first(where: { $0.id == iconPictogramID }) {
            return chosen
        }
        return page.visibleCards.first
    }

    private func iconChoice(_ pictogram: Pictogram?, label: String) -> some View {
        let selected = iconPictogramID == pictogram?.id
        return Button {
            iconPictogramID = pictogram?.id
        } label: {
            VStack(spacing: 4) {
                PageIconView(pictogram: pictogram ?? page.visibleCards.first, side: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(selected ? Color.accentColor : Color.black.opacity(0.12), lineWidth: selected ? 3 : 1)
                    )
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
                    .frame(width: 64)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func apply() {
        let store = PictoStore(context: context)
        let targetRows = isBar ? 1 : rows
        if columns != page.columns || targetRows != page.rows {
            guard store.resize(page, columns: columns, rows: targetRows) else {
                message = "Il y a plus de pictogrammes que de cases. Retirez des pictogrammes ou gardez une grille plus grande."
                return
            }
        }
        if !isBar {
            page.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            page.isHidden = isHidden
            page.color = color
            page.iconPictogramID = iconPictogramID
        }
        store.save()
        dismiss()
    }
}
