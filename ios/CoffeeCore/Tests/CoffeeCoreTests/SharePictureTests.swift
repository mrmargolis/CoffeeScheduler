import Testing

@testable import CoffeeCore

@Suite struct SharePictureTests {
    @Test func widensATallCard() {
        // A month and its bags, taller than 3:4: borders at the sides
        let canvas = SharePicture.canvas(width: 393, height: 800)
        #expect(canvas.width == 600 && canvas.height == 800)
    }

    @Test func heightensAWideCard() {
        // One day's row: borders above and below
        let canvas = SharePicture.canvas(width: 393, height: 200)
        #expect(canvas.width == 393 && abs(canvas.height - 524) < 0.001)
    }

    @Test func leavesA3By4CardAlone() {
        let canvas = SharePicture.canvas(width: 300, height: 400)
        #expect(canvas.width == 300 && canvas.height == 400)
    }
}
