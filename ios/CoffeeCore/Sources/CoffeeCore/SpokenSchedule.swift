/// One day of the schedule as a sentence, for Siri to say.
public enum SpokenSchedule {
    public enum Day: String, Sendable, CaseIterable {
        case today
        case tomorrow

        /// Days after today.
        public var offset: Int { self == .today ? 0 : 1 }
        var name: String { self == .today ? "Today" : "Tomorrow" }
    }

    /// What's planned on `day`, which is nil when the schedule doesn't reach it.
    public static func sentence(for day: ScheduleDay?, on when: Day) -> String {
        guard let day else { return "\(when.name) isn't in the schedule yet." }
        if day.isSkip { return "\(when.name) is a skip day, so no coffee is planned." }
        guard !day.consumptions.isEmpty else { return "No coffee is ready \(when.rawValue)." }

        var sentence: String
        if day.consumptions.count == 1, let cup = day.consumptions.first {
            sentence = "\(when.name) is \(name(cup)), \(grams(cup.grams))."
        } else {
            let cups = day.consumptions.map { "\(grams($0.grams)) of \(name($0))" }
            sentence = "\(when.name) is \(list(cups))."
        }
        for cup in day.consumptions {
            if let early = cup.daysEarly, early > 0 {
                sentence += " \(cup.beanName) starts \(early) \(early == 1 ? "day" : "days") before it has finished resting."
            }
        }
        return sentence
    }

    /// "Guji Hambela from Square Mile".
    private static func name(_ cup: Consumption) -> String {
        cup.roaster.isEmpty ? cup.beanName : "\(cup.beanName) from \(cup.roaster)"
    }

    /// "45 grams", "1 gram", "22.5 grams".
    private static func grams(_ value: Double) -> String {
        let tenths = (value * 10).rounded() / 10
        let number = tenths == tenths.rounded() ? String(Int(tenths)) : String(tenths)
        return "\(number) \(tenths == 1 ? "gram" : "grams")"
    }

    /// "a and b", "a, b and c".
    private static func list(_ items: [String]) -> String {
        guard let last = items.last, items.count > 1 else { return items.first ?? "" }
        return "\(items.dropLast().joined(separator: ", ")) and \(last)"
    }
}
