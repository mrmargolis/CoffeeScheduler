import Testing

@testable import CoffeeCore

@Suite struct SpokenScheduleTests {
    private func day(_ cups: [Consumption], isSkip: Bool = false) -> ScheduleDay {
        ScheduleDay(
            date: "2026-10-12", consumptions: cups, isGap: cups.isEmpty && !isSkip, isSurplus: false, isActual: false, isSkip: isSkip
        )
    }

    private func cup(_ name: String, _ roaster: String, _ grams: Double, early: Int? = nil) -> Consumption {
        Consumption(beanID: name, beanName: name, roaster: roaster, grams: grams, daysEarly: early)
    }

    @Test func namesTheBagItsRoasterAndTheGrams() {
        let sentence = SpokenSchedule.sentence(for: day([cup("La Esperanza", "Tim Wendelboe", 45)]), on: .today)
        #expect(sentence == "Today is La Esperanza from Tim Wendelboe, 45 grams.")
    }

    @Test func listsEachBagOnASharedDay() {
        let cups = [cup("Guji Hambela", "Square Mile", 15), cup("La Esperanza", "Tim Wendelboe", 30)]
        #expect(
            SpokenSchedule.sentence(for: day(cups), on: .tomorrow)
                == "Tomorrow is 15 grams of Guji Hambela from Square Mile and 30 grams of La Esperanza from Tim Wendelboe."
        )
    }

    @Test func joinsThreeBagsWithACommaAndAnAnd() {
        let cups = [cup("A", "", 15), cup("B", "", 15), cup("C", "", 22.5)]
        #expect(SpokenSchedule.sentence(for: day(cups), on: .today) == "Today is 15 grams of A, 15 grams of B and 22.5 grams of C.")
    }

    @Test func saysWhenABagStartsEarly() {
        let sentence = SpokenSchedule.sentence(for: day([cup("Gichathaini AA", "Coffee Collective", 45, early: 3)]), on: .tomorrow)
        #expect(
            sentence
                == "Tomorrow is Gichathaini AA from Coffee Collective, 45 grams. Gichathaini AA starts 3 days before it has finished resting."
        )
        let one = SpokenSchedule.sentence(for: day([cup("A", "", 1, early: 1)]), on: .today)
        #expect(one == "Today is A, 1 gram. A starts 1 day before it has finished resting.")
    }

    @Test func saysASkipDayIsSkipped() {
        #expect(SpokenSchedule.sentence(for: day([], isSkip: true), on: .tomorrow) == "Tomorrow is a skip day, so no coffee is planned.")
    }

    @Test func saysWhenNothingIsReady() {
        #expect(SpokenSchedule.sentence(for: day([]), on: .today) == "No coffee is ready today.")
    }

    @Test func saysWhenTheDayIsBeyondTheSchedule() {
        #expect(SpokenSchedule.sentence(for: nil, on: .tomorrow) == "Tomorrow isn't in the schedule yet.")
    }
}
