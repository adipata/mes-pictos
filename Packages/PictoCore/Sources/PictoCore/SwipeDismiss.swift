import CoreGraphics

/// Decides when a drag on the shown card is a swipe that closes it.
///
/// Young children's fingers wobble while tapping, so a drag only starts after `startDistance`
/// (below that it stays a tap, which speaks the card again), and closing needs either a clear
/// distance or a quick flick.
public enum SwipeDismiss {
    /// How far the finger must move before the touch counts as a drag instead of a tap.
    public static let startDistance: CGFloat = 20
    /// Smallest distance that closes the card, whatever its size.
    public static let minimumDismissDistance: CGFloat = 90
    /// Distance that closes the card, as a fraction of its side (used when larger than the minimum).
    public static let dismissFraction: CGFloat = 0.22
    /// A flick closes the card when the predicted end of the gesture is this far (fraction of the side)…
    public static let flickPredictedFraction: CGFloat = 0.5
    /// …and the finger really moved at least this much.
    public static let flickMinimumDistance: CGFloat = 40

    /// The distance needed to close a card of the given side.
    public static func dismissDistance(cardSide: CGFloat) -> CGFloat {
        max(minimumDismissDistance, cardSide * dismissFraction)
    }

    /// Whether a finished drag closes the card.
    /// - Parameters:
    ///   - translation: where the finger ended, relative to where it started.
    ///   - predictedEndTranslation: where the gesture would end given its speed.
    ///   - cardSide: the side of the shown card, in points.
    public static func shouldDismiss(translation: CGSize, predictedEndTranslation: CGSize, cardSide: CGFloat) -> Bool {
        let distance = length(translation)
        if distance >= dismissDistance(cardSide: cardSide) { return true }
        let predicted = length(predictedEndTranslation)
        return distance >= flickMinimumDistance && predicted >= cardSide * flickPredictedFraction
    }

    /// The offset that moves the card fully off a screen of the given size, in the swipe's direction.
    public static func flyAwayOffset(translation: CGSize, predictedEndTranslation: CGSize, containerSize: CGSize) -> CGSize {
        // Prefer the predicted direction (a flick), fall back to the finger's direction.
        let direction = length(predictedEndTranslation) > length(translation) ? predictedEndTranslation : translation
        let directionLength = length(direction)
        guard directionLength > 0 else { return CGSize(width: 0, height: containerSize.height) }
        let distance = length(containerSize) * 1.1
        return CGSize(width: direction.width / directionLength * distance,
                      height: direction.height / directionLength * distance)
    }

    private static func length(_ size: CGSize) -> CGFloat {
        (size.width * size.width + size.height * size.height).squareRoot()
    }
}
