/// The figures over the shared picture of the Beans screen: how many bags,
/// how much coffee, and how long it lasts.
public struct BacklogSummary: Equatable, Sendable {
    public let queuedBags: Int
    public let frozenBags: Int
    /// Coffee left in every bag, frozen ones included.
    public let grams: Double
    /// The last day with coffee (the runway's); nil when none is ready.
    public let lastCoffeeDay: String?
    /// Days with coffee from today through `lastCoffeeDay`.
    public let coffeeDays: Int?

    public init(beans: [Bean], lastCoffeeDay: String?, today: String) {
        queuedBags = beans.filter { !$0.isFrozen }.count
        frozenBags = beans.filter(\.isFrozen).count
        grams = beans.reduce(0) { $0 + max(0, $1.remainingGrams) }
        self.lastCoffeeDay = lastCoffeeDay
        coffeeDays = lastCoffeeDay.map { DateUtils.daysBetween(today, $0) + 1 }.flatMap { $0 > 0 ? $0 : nil }
    }
}
