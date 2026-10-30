import CoffeeCore
import SwiftUI
import UIKit

/// A picture of a month, its bags or one day to send to someone. It's drawn
/// when the share button is tapped, not each time the screen redraws.
struct ScheduleSnapshot {
    enum Subject: Hashable, Sendable {
        /// The first of the month.
        case month(String)
        /// The bags drunk in the month, as listed under it, the first of the
        /// month given.
        case bags(String)
        case day(String)
    }

    /// An iPhone's width in points, so the picture reads like the screen.
    static let width: CGFloat = 393

    let subject: Subject
    let model: AppModel
    /// "October 2026" or "Monday October 12": the heading.
    let title: String

    @MainActor
    init(_ subject: Subject, model: AppModel) {
        self.subject = subject
        self.model = model
        switch subject {
        case .month(let month), .bags(let month): title = Format.monthTitle(month)
        case .day(let date): title = Format.longDay(date)
        }
    }

    /// The card centred on a 3:4 picture, for an Instagram post: a border
    /// of the background at the sides of a month, above and below a day.
    /// The card is drawn once and then placed, as drawing it is the slow part.
    @MainActor
    func image() throws -> UIImage {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let card = renderer.uiImage else { throw CocoaError(.fileWriteUnknown) }
        let canvas = SharePicture.canvas(width: card.size.width, height: card.size.height)
        // Whole points wide, so at 3x the pixels are exactly 3:4
        let width = canvas.width.rounded(.up)
        let size = CGSize(width: width, height: width / SharePicture.aspect)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 3
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(Theme.ground).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            card.draw(at: CGPoint(x: (size.width - card.size.width) / 2, y: (size.height - card.size.height) / 2))
        }
    }

    @MainActor
    func png() throws -> Data {
        guard let data = try image().pngData() else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    private var eyebrow: String {
        if case .bags = subject { "Coffee bags" } else { "Coffee schedule" }
    }

    @MainActor
    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(eyebrow: eyebrow, title: title)
            switch subject {
            case .month(let month): MonthPicture(month: month)
            case .bags(let month): BagsPicture(month: month)
            case .day(let date): DayPicture(date: date)
            }
        }
        .padding(20)
        .frame(width: Self.width)
        .background(Theme.ground)
        .foregroundStyle(Theme.text)
        .environment(model)
        .environment(\.colorScheme, .dark)
    }
}

/// The month grid, as on the Schedule screen but with nothing to tap.
private struct MonthPicture: View {
    let month: String

    var body: some View {
        MonthView(month: .constant(month), openBean: { _ in }, openDay: { _ in }, showsHeader: false)
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

/// The month's bags, as listed under its grid.
private struct BagsPicture: View {
    @Environment(AppModel.self) private var model
    let month: String

    var body: some View {
        VStack(spacing: 0) {
            BagKey(runs: model.bagRuns(inMonth: month)) { _ in }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

/// One day's row from the list, on a card of its own.
private struct DayPicture: View {
    @Environment(AppModel.self) private var model
    let date: String

    var body: some View {
        if let day = model.schedule.first(where: { $0.date == date }) {
            let runs = Dictionary(Scheduler.bagRuns(model.schedule).map { ($0.beanID, $0) }, uniquingKeysWith: { a, _ in a })
            DayRow(day: day, runs: runs, openBean: { _ in }, openDay: {}, dimsPast: false)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        }
    }
}

/// The share button for a month or a day: the usual arrow out of a box. A
/// month shares two pictures, its grid and then its bags, to post together.
/// They're handed to the share sheet as images, so it offers Save Image.
struct ShareScheduleLink: View {
    @Environment(AppModel.self) private var model
    let subject: ScheduleSnapshot.Subject
    @State private var drawing = false

    var body: some View {
        let snapshot = ScheduleSnapshot(subject, model: model)
        Button {
            share(snapshot)
        } label: {
            Group {
                if drawing {
                    ProgressView()
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .disabled(drawing)
        .accessibilityLabel("Share \(snapshot.title)")
    }

    private func share(_ snapshot: ScheduleSnapshot) {
        drawing = true
        Task {
            // Shows the spinner before the drawing holds up the screen
            try? await Task.sleep(for: .milliseconds(50))
            let images = pictures(snapshot).compactMap { try? $0.image() }
            drawing = false
            if !images.isEmpty { ShareSheet.present(images) }
        }
    }

    private func pictures(_ snapshot: ScheduleSnapshot) -> [ScheduleSnapshot] {
        guard case .month(let month) = subject, !model.bagRuns(inMonth: month).isEmpty else { return [snapshot] }
        return [snapshot, ScheduleSnapshot(.bags(month), model: model)]
    }
}

/// The system share sheet, over whatever is showing.
@MainActor
enum ShareSheet {
    static func present(_ items: [Any]) {
        let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        guard var top = windows.first(where: \.isKeyWindow)?.rootViewController else { return }
        while let presented = top.presentedViewController { top = presented }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
    }
}
