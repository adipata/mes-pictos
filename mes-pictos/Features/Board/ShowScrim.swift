import SwiftUI

/// The dimmed background behind a shown card or sentence, with the gestures that close it,
/// and the hint at the bottom of the screen.
struct ShowScrim: View {
    let dismissMode: DismissMode
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    if dismissMode == .tapOutside { onClose() }
                }
                .onLongPressGesture(minimumDuration: 1) {
                    onClose()
                }
                .gesture(
                    DragGesture(minimumDistance: 40).onEnded { value in
                        if dismissMode == .tapOutside, value.translation.height > 120 { onClose() }
                    }
                )
                .transition(.opacity)

            VStack {
                Spacer()
                Text(dismissMode == .tapOutside ? "Touchez à côté pour fermer" : "Appui long à côté pour fermer")
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.bottom, 16)
            }
            .allowsHitTesting(false)
        }
    }
}
