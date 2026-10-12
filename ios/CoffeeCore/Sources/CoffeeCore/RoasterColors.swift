/// One roaster's colours, as hex strings: `border` is the rail beside a bag,
/// `bg` the (dark theme) tint behind it, `text` the label on that tint.
public struct RoasterColor: Hashable, Sendable {
    public var bg: String
    public var border: String
    public var text: String

    /// Palette order is load-bearing: changing it reshuffles every roaster's colour.
    public static let palette = [
        RoasterColor(bg: "#2d2114", border: "#e1b581", text: "#efdcc4"),  // amber
        RoasterColor(bg: "#172632", border: "#8fc4f1", text: "#d5e5f3"),  // blue
        RoasterColor(bg: "#19281c", border: "#96cea1", text: "#d8ecdc"),  // green
        RoasterColor(bg: "#311e1f", border: "#efa8ac", text: "#f4dcde"),  // rose
        RoasterColor(bg: "#262131", border: "#c6b2ed", text: "#e5ddf6"),  // violet
        RoasterColor(bg: "#301f18", border: "#edad90", text: "#f3ded3"),  // orange
        RoasterColor(bg: "#112927", border: "#78d0ca", text: "#cdeeeb"),  // teal
        RoasterColor(bg: "#12272e", border: "#7ccbe4", text: "#cfebf3"),  // cyan
        RoasterColor(bg: "#202333", border: "#adbaf5", text: "#dee3fa"),  // indigo
        RoasterColor(bg: "#311e1d", border: "#f0a9a2", text: "#f5dcda"),  // red
    ]

    /// Coprime with the palette size, so probing visits every slot, and large
    /// enough to jump to a clearly different hue rather than the next one.
    static let probeStride = 3

    /// A string hash: `hash = (hash << 5) - hash + charCode` over
    /// UTF-16 code units in 32-bit arithmetic, then its absolute value.
    static func hash(_ string: String) -> Int {
        var hash: Int32 = 0
        for unit in string.utf16 {
            hash = (hash &<< 5) &- hash &+ Int32(unit)
        }
        return Int(abs(Int64(hash)))
    }

    /// One roaster's colour, independent of who else is on screen.
    public static func forRoaster(_ roaster: String) -> RoasterColor {
        palette[hash(roaster) % palette.count]
    }

    /// Colours for a known set of roasters with no two sharing one (up to the
    /// palette size). Each keeps its hashed slot when free; otherwise probing
    /// steps by `probeStride`, since neighbouring slots are neighbouring hues.
    /// Deterministic for a given ordered set.
    public static func assign(_ roasters: [String]) -> [String: RoasterColor] {
        var taken = Set<Int>()
        var assigned: [String: RoasterColor] = [:]
        for roaster in roasters where assigned[roaster] == nil {
            let preferred = hash(roaster) % palette.count
            var slot = preferred
            for probe in 0..<palette.count {
                let candidate = (preferred + probe * probeStride) % palette.count
                if !taken.contains(candidate) {
                    slot = candidate
                    break
                }
            }
            taken.insert(slot)
            assigned[roaster] = palette[slot]
        }
        return assigned
    }
}
