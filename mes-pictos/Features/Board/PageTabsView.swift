import SwiftUI
import SwiftData

/// The page tabs. In parent mode they are also drop targets: hold a dragged card over a tab
/// to open that page, then drop it in a slot.
struct PageTabsView: View {
    let pages: [Page]
    let selectedID: UUID?

    @Environment(BoardModel.self) private var board
    @Environment(\.modelContext) private var context

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                    PageTab(
                        page: page,
                        color: page.tabColor(atIndex: index),
                        isSelected: page.id == selectedID,
                        isFirst: index == 0,
                        isLast: index == pages.count - 1
                    )
                    .id(page.id)
                }
                if board.isParentMode {
                    Button {
                        let page = PictoStore(context: context).addPage(title: "Nouvelle page")
                        board.selectedPageID = page.id
                        board.pageSettings = page
                    } label: {
                        Label("Page", systemImage: "plus")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 4)
            }
            .onChange(of: selectedID, initial: true) { _, id in
                guard let id else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PageTab: View {
    let page: Page
    let color: PageColor
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool

    @Environment(BoardModel.self) private var board
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isDropTarget = false
    @State private var springLoad: Task<Void, Never>?

    private var isCompact: Bool { sizeClass == .compact }

    var body: some View {
        if board.isParentMode {
            tab
                .contextMenu {
                    Button {
                        board.pageSettings = page
                    } label: {
                        Label("Réglages de la page", systemImage: "slider.horizontal.3")
                    }
                    Button {
                        PictoStore(context: context).setHidden(page, !page.isHidden)
                    } label: {
                        if page.isHidden {
                            Label("Afficher pour l'enfant", systemImage: "eye")
                        } else {
                            Label("Masquer pour l'enfant", systemImage: "eye.slash")
                        }
                    }
                    if !isFirst {
                        Button {
                            PictoStore(context: context).movePage(page, by: -1)
                        } label: {
                            Label("Déplacer à gauche", systemImage: "arrow.left")
                        }
                    }
                    if !isLast {
                        Button {
                            PictoStore(context: context).movePage(page, by: 1)
                        } label: {
                            Label("Déplacer à droite", systemImage: "arrow.right")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        board.pageToDelete = page
                    } label: {
                        Label("Supprimer la page", systemImage: "trash")
                    }
                }
                .dropDestination(for: String.self) { items, _ in
                    springLoad?.cancel()
                    guard let first = items.first, let id = UUID(uuidString: first) else { return false }
                    let store = PictoStore(context: context)
                    guard let moving = store.placement(withID: id) else { return false }
                    if !store.move(moving, toPage: page) {
                        board.alertMessage = "La page « \(page.displayTitle) » est pleine. Agrandissez sa grille ou libérez une case."
                        return false
                    }
                    board.selectedPageID = page.id
                    return true
                } isTargeted: { targeted in
                    isDropTarget = targeted
                    springLoad?.cancel()
                    if targeted {
                        springLoad = Task {
                            try? await Task.sleep(for: .milliseconds(700))
                            if !Task.isCancelled {
                                board.selectedPageID = page.id
                            }
                        }
                    }
                }
        } else {
            tab
        }
    }

    private var tab: some View {
        Button {
            board.selectedPageID = page.id
        } label: {
            HStack(spacing: 10) {
                PageIconView(pictogram: page.iconPictogram, side: isCompact ? 34 : 44)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                if page.isHidden {
                    Image(systemName: "eye.slash")
                }
                Text(page.displayTitle)
                    .lineLimit(1)
            }
            .font(.system(size: isCompact ? 16 : 20, weight: .bold, design: .rounded))
            .foregroundStyle(isSelected ? color.textColor : Color.primary)
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? color.color : color.color.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isDropTarget ? Color.accentColor : color.color.opacity(isSelected ? 0 : 0.6), lineWidth: isDropTarget ? 3 : 2)
            )
            .shadow(color: isSelected ? color.color.opacity(0.35) : .clear, radius: 6, y: 3)
            .scaleEffect(isSelected ? 1.04 : 1)
            .opacity(page.isHidden ? 0.6 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(page.displayTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
