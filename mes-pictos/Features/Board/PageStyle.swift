import SwiftUI

extension PageColor {
    /// Saturated colour for the selected tab and the colour swatches.
    var color: Color {
        switch self {
        case .red: return Color(red: 0.90, green: 0.29, blue: 0.27)
        case .orange: return Color(red: 0.96, green: 0.56, blue: 0.14)
        case .yellow: return Color(red: 0.93, green: 0.75, blue: 0.10)
        case .green: return Color(red: 0.30, green: 0.69, blue: 0.31)
        case .teal: return Color(red: 0.13, green: 0.64, blue: 0.66)
        case .blue: return Color(red: 0.25, green: 0.49, blue: 0.89)
        case .purple: return Color(red: 0.56, green: 0.36, blue: 0.80)
        case .pink: return Color(red: 0.90, green: 0.40, blue: 0.62)
        case .brown: return Color(red: 0.60, green: 0.43, blue: 0.29)
        }
    }

    /// Text colour that reads well on `color`.
    var textColor: Color {
        self == .yellow ? Color.black : Color.white
    }
}

/// Small picture of a page's pictogram, used on the tabs and in the page settings.
struct PageIconView: View {
    let pictogram: Pictogram?
    let side: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: side * 0.2, style: .continuous)
                .fill(Color.white)
            if let pictogram, let image = ImageCache.shared.image(for: pictogram) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(side * 0.1)
            } else {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: side * 0.5))
                    .foregroundStyle(Color.gray.opacity(0.5))
            }
        }
        .frame(width: side, height: side)
    }
}
