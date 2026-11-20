import SwiftUI
import SwiftData

/// The page menu: one large button showing the current page, which opens a dropdown list of all the
/// pages. The same on iPhone and iPad, so a row of tabs never has to scroll on a small screen.
///
/// In parent mode the list also holds "Nouvelle page", each row has a context menu (settings, hide,
/// move, delete), and the button and the rows are drop targets: hold a dragged card over the button
/// to open the list, then over a page to open that page, then drop the card in a slot.
struct PageMenuView: View {
    let pages: [Page]
    let selectedID: UUID?

    @Environment(BoardModel.self) private var board
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var isOpen = false
    @State private var isDropTarget = false
    /// Runs once the list has closed: a sheet, alert or dialog cannot open while the popover is still on screen.
    @State private var afterClose: (() -> Void)?

    private var isCompact: Bool { sizeClass == .compact }
    private var selectedIndex: Int? { pages.firstIndex { $0.id == selectedID } }
    private var selectedPage: Page? { selectedIndex.map { pages[$0] } }

    var body: some View {
        Button {
            isOpen.toggle()
        } label: {
            currentLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel(selectedPage.map { "Page \($0.displayTitle)" } ?? "Pages")
        .accessibilityHint("Ouvre la liste des pages")
        .modifier(SpringLoadTarget(enabled: board.isParentMode, isTargeted: $isDropTarget) {
            isOpen = true
        })
        .popover(isPresented: $isOpen, arrowEdge: .top) {
            PageMenuList(pages: pages, selectedID: selectedID, isCompact: isCompact) { then in
                afterClose = then
                isOpen = false
            }
            .onDisappear {
                let action = afterClose
                afterClose = nil
                action?()
            }
            .presentationCompactAdaptation(.popover)
            .environment(board)
            .modelContext(context)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The closed menu: the current page, large, with a chevron that says it opens.
    private var currentLabel: some View {
        let color = selectedIndex.map { pages[$0].tabColor(atIndex: $0) }
        return HStack(spacing: 12) {
            PageIconView(pictogram: selectedPage?.iconPictogram, side: isCompact ? 44 : 56)
                .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
            if selectedPage?.isHidden == true {
                Image(systemName: "eye.slash")
            }
            Text(selectedPage?.displayTitle ?? "Pages")
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Image(systemName: "chevron.down")
                .font(.system(size: isCompact ? 18 : 22, weight: .heavy))
                .rotationEffect(.degrees(isOpen ? 180 : 0))
                .padding(.leading, 2)
        }
        .font(.system(size: isCompact ? 20 : 24, weight: .bold, design: .rounded))
        .foregroundStyle(color?.textColor ?? Color.primary)
        .padding(.leading, 8)
        .padding(.trailing, 18)
        .padding(.vertical, 8)
        .frame(minHeight: isCompact ? 60 : 72)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(color?.color ?? Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: isDropTarget ? 3 : 0)
        )
        .shadow(color: (color?.color ?? .clear).opacity(0.35), radius: 6, y: 3)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isOpen)
    }
}

/// The open dropdown: one large row per page, easy to tap.
private struct PageMenuList: View {
    let pages: [Page]
    let selectedID: UUID?
    let isCompact: Bool
    /// Closes the list, then runs the optional action.
    let dismiss: ((() -> Void)?) -> Void

    @Environment(BoardModel.self) private var board
    @Environment(\.modelContext) private var context

    private var rowHeight: CGFloat { isCompact ? 68 : 80 }
    private var spacing: CGFloat { 8 }
    private var rowCount: Int { pages.count + (board.isParentMode ? 1 : 0) }

    /// Popovers need an explicit height: all the rows if they fit, otherwise the list scrolls.
    private var height: CGFloat {
        let content = CGFloat(rowCount) * rowHeight + CGFloat(max(rowCount - 1, 0)) * spacing + 24
        return min(content, isCompact ? 480 : 640)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: spacing) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                        PageMenuRow(
                            page: page,
                            color: page.tabColor(atIndex: index),
                            isSelected: page.id == selectedID,
                            isFirst: index == 0,
                            isLast: index == pages.count - 1,
                            height: rowHeight,
                            isCompact: isCompact,
                            dismiss: dismiss
                        )
                        .id(page.id)
                    }
                    if board.isParentMode {
                        Button {
                            let page = PictoStore(context: context).addPage(title: "Nouvelle page")
                            board.selectedPageID = page.id
                            dismiss { board.pageSettings = page }
                        } label: {
                            Label("Nouvelle page", systemImage: "plus")
                                .font(.system(size: isCompact ? 20 : 22, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity, minHeight: rowHeight)
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                                )
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                    }
                }
                .padding(12)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onAppear {
                if let selectedID { proxy.scrollTo(selectedID, anchor: .center) }
            }
        }
        .frame(width: isCompact ? 330 : 420, height: height)
    }
}

private struct PageMenuRow: View {
    let page: Page
    let color: PageColor
    let isSelected: Bool
    let isFirst: Bool
    let isLast: Bool
    let height: CGFloat
    let isCompact: Bool
    /// Closes the list, then runs the optional action.
    let dismiss: ((() -> Void)?) -> Void

    @Environment(BoardModel.self) private var board
    @Environment(\.modelContext) private var context
    @State private var isDropTarget = false
    @State private var springLoad: Task<Void, Never>?

    var body: some View {
        if board.isParentMode {
            row
                .contextMenu {
                    Button {
                        dismiss { board.pageSettings = page }
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
                            Label("Monter", systemImage: "arrow.up")
                        }
                    }
                    if !isLast {
                        Button {
                            PictoStore(context: context).movePage(page, by: 1)
                        } label: {
                            Label("Descendre", systemImage: "arrow.down")
                        }
                    }
                    Divider()
                    Button(role: .destructive) {
                        dismiss { board.pageToDelete = page }
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
                        dismiss { board.alertMessage = "La page « \(page.displayTitle) » est pleine. Agrandissez sa grille ou libérez une case." }
                        return false
                    }
                    board.selectedPageID = page.id
                    dismiss(nil)
                    return true
                } isTargeted: { targeted in
                    isDropTarget = targeted
                    springLoad?.cancel()
                    guard targeted else { return }
                    // Holding a card over a page opens it, so the card can be dropped in a chosen slot.
                    springLoad = Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        if !Task.isCancelled {
                            board.selectedPageID = page.id
                            dismiss(nil)
                        }
                    }
                }
        } else {
            row
        }
    }

    private var row: some View {
        Button {
            board.selectedPageID = page.id
            dismiss(nil)
        } label: {
            HStack(spacing: 14) {
                PageIconView(pictogram: page.iconPictogram, side: height - 16)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
                if page.isHidden {
                    Image(systemName: "eye.slash")
                }
                Text(page.displayTitle)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: isCompact ? 20 : 22, weight: .heavy))
                }
            }
            .font(.system(size: isCompact ? 20 : 24, weight: .bold, design: .rounded))
            .foregroundStyle(isSelected ? color.textColor : Color.primary)
            .padding(.leading, 8)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(isSelected ? color.color : color.color.opacity(0.22))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(isDropTarget ? Color.accentColor : color.color.opacity(isSelected ? 0 : 0.6), lineWidth: isDropTarget ? 3 : 2)
            )
            .opacity(page.isHidden ? 0.6 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(page.displayTitle)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "Spring-loading", as in the Files app: holding a dragged card over the view for a moment runs
/// `action`. The view does not take the drop itself.
private struct SpringLoadTarget: ViewModifier {
    let enabled: Bool
    @Binding var isTargeted: Bool
    let action: () -> Void

    @State private var springLoad: Task<Void, Never>?

    func body(content: Content) -> some View {
        if enabled {
            content
                .dropDestination(for: String.self) { _, _ in
                    springLoad?.cancel()
                    return false
                } isTargeted: { targeted in
                    isTargeted = targeted
                    springLoad?.cancel()
                    guard targeted else { return }
                    springLoad = Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        if !Task.isCancelled { action() }
                    }
                }
        } else {
            content
        }
    }
}
