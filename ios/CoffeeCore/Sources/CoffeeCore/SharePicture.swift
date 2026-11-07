import Foundation

/// The shape of a picture shared from the app: 3 wide by 4 tall, as an
/// Instagram post is, so it posts without a border added by hand.
public enum SharePicture {
    /// Width over height.
    public static let aspect = 3.0 / 4.0

    /// The smallest 3:4 canvas a card of this size fits in: as wide as the
    /// card and taller, or as tall and wider, with the card centred on it.
    public static func canvas(width: Double, height: Double) -> (width: Double, height: Double) {
        guard width > 0, height > 0 else { return (width, height) }
        return width / height > aspect ? (width, width / aspect) : (height * aspect, height)
    }
}
