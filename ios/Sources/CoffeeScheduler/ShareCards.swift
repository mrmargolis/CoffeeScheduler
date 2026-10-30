import CoffeeCore
import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A picture of a month, its bags or one day to send to someone. It's drawn when
/// the share sheet asks for it, not each time the screen redraws.
struct ScheduleSnapshot: Transferable, Sendable {
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

    /// The file's name: a month's bags are named apart from the month.
    var fileName: String {
        if case .bags = subject { "Coffee \(title) bags.png" } else { "Coffee \(title).png" }
    }

    @MainActor
    init(_ subject: Subject, model: AppModel) {
        self.subject = subject
        self.model = model
        switch subject {
        case .month(let month), .bags(let month): title = Format.monthTitle(month)
        case .day(let date): title = Format.longDay(date)
        }
    }

    /// A PNG file first, which the share sheet offers to save to Photos,
    /// as it doesn't for the bare data.
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { try await SentTransferredFile($0.file()) }
        DataRepresentation(exportedContentType: .png) { try await $0.png() }
            .suggestedFileName(\.fileName)
    }

    /// The picture written to a folder of its own, by its file's name.
    @MainActor
    func file() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(fileName)
        try png().write(to: url)
        return url
    }

    /// The card centred on a 3:4 picture, for an Instagram post: a border
    /// of the background at the sides of a month, above and below a day.
    @MainActor
    func png() throws -> Data {
        guard let size = ImageRenderer(content: card).uiImage?.size else { throw CocoaError(.fileWriteUnknown) }
        let canvas = SharePicture.canvas(width: size.width, height: size.height)
        // Whole points wide, so at 3x the pixels are exactly 3:4
        let width = canvas.width.rounded(.up)
        let renderer = ImageRenderer(
            content:
                card
                .frame(width: width, height: width / SharePicture.aspect)
                .background(Theme.ground)
        )
        renderer.scale = 3
        guard let data = renderer.uiImage?.pngData() else { throw CocoaError(.fileWriteUnknown) }
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
struct ShareScheduleLink: View {
    @Environment(AppModel.self) private var model
    let subject: ScheduleSnapshot.Subject

    var body: some View {
        let snapshot = ScheduleSnapshot(subject, model: model)
        ShareLink(
            items: pictures(snapshot), preview: { SharePreview($0.title) },
            label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        )
        .accessibilityLabel("Share \(snapshot.title)")
    }

    private func pictures(_ snapshot: ScheduleSnapshot) -> [ScheduleSnapshot] {
        guard case .month(let month) = subject, !model.bagRuns(inMonth: month).isEmpty else { return [snapshot] }
        return [snapshot, ScheduleSnapshot(.bags(month), model: model)]
    }
}
