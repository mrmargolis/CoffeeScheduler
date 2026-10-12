import CoffeeCore
import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A picture of a month or of one day to send to someone. It's drawn when
/// the share sheet asks for it, not each time the screen redraws.
struct ScheduleSnapshot: Transferable, Sendable {
    enum Subject: Hashable, Sendable {
        /// The first of the month.
        case month(String)
        case day(String)
    }

    /// An iPhone's width in points, so the picture reads like the screen.
    static let width: CGFloat = 393

    let subject: Subject
    let model: AppModel
    /// "October 2026" or "Monday October 12": the heading and the file's name.
    let title: String

    @MainActor
    init(_ subject: Subject, model: AppModel) {
        self.subject = subject
        self.model = model
        switch subject {
        case .month(let month): title = Format.monthTitle(month)
        case .day(let date): title = Format.longDay(date)
        }
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { try await $0.png() }
            .suggestedFileName { "Coffee \($0.title).png" }
    }

    @MainActor
    func png() throws -> Data {
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { throw CocoaError(.fileWriteUnknown) }
        return data
    }

    @MainActor
    private var card: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScreenHeader(eyebrow: "Coffee schedule", title: title)
            switch subject {
            case .month(let month): MonthPicture(month: month)
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

/// The month grid and its bags, as on the Schedule screen but with nothing to tap.
private struct MonthPicture: View {
    @Environment(AppModel.self) private var model
    let month: String

    var body: some View {
        let runs = model.bagRuns(inMonth: month)
        VStack(spacing: 12) {
            MonthView(month: .constant(month), openBean: { _ in }, openDay: { _ in }, showsHeader: false)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            if !runs.isEmpty {
                VStack(spacing: 0) {
                    BagKey(runs: runs) { _ in }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            }
        }
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

/// The share button for a month or a day: the usual arrow out of a box.
struct ShareScheduleLink: View {
    @Environment(AppModel.self) private var model
    let subject: ScheduleSnapshot.Subject

    var body: some View {
        let snapshot = ScheduleSnapshot(subject, model: model)
        ShareLink(item: snapshot, preview: SharePreview(snapshot.title)) {
            Image(systemName: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Share \(snapshot.title)")
    }
}
