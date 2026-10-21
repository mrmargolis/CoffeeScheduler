import CoffeeCore
import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A picture of the Beans screen to post: the backlog's figures over the
/// queue and the freezer, at least as tall as a 4:5 post. It's drawn when
/// the share sheet asks for it.
struct BeansSnapshot: Transferable, Sendable {
    /// Bags past these are counted, not drawn, so a long backlog still
    /// makes a post rather than a scroll.
    static let shownQueue = 8
    static let shownFrozen = 3

    let model: AppModel

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { try await $0.png() }
            .suggestedFileName { _ in "Coffee backlog.png" }
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
        BeansPicture()
            .padding(20)
            .frame(width: ScheduleSnapshot.width)
            .frame(minHeight: ScheduleSnapshot.width * 5 / 4, alignment: .top)
            .background(Theme.ground)
            .foregroundStyle(Theme.text)
            .environment(model)
            .environment(\.colorScheme, .dark)
    }
}

/// The queue and the freezer as on the Beans screen, under the backlog's figures.
private struct BeansPicture: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let queue = model.activeBeans.filter { !$0.isFrozen }
        let frozen = model.activeBeans.filter(\.isFrozen)
        let starts = Scheduler.startDates(model.schedule)
        let summary = BacklogSummary(beans: model.activeBeans, lastCoffeeDay: model.runway?.lastCoffeeDay, today: model.today)
        VStack(alignment: .leading, spacing: 10) {
            ScreenHeader(eyebrow: "Coffee backlog · \(Format.mediumDay(model.today))", title: "Beans")
                .padding(.bottom, 6)
            BacklogFigures(summary: summary)
                .padding(.bottom, 6)
            ForEach(queue.prefix(BeansSnapshot.shownQueue)) { QueueCard(bean: $0, start: starts[$0.id]) }
            more(queue.count - BeansSnapshot.shownQueue, of: "in the queue")
            if !frozen.isEmpty {
                SectionLabel(title: "Frozen").padding(.horizontal, 4).padding(.top, 6)
                ForEach(frozen.prefix(BeansSnapshot.shownFrozen)) { FrozenCard(bean: $0) }
                more(frozen.count - BeansSnapshot.shownFrozen, of: "frozen")
            }
            Spacer(minLength: 6)
            Label("Coffee Scheduler", systemImage: "cup.and.saucer.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.text3)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func more(_ count: Int, of place: String) -> some View {
        if count > 0 {
            Text("+ \(count) more \(place)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.text2)
                .padding(.horizontal, 4)
        }
    }
}

/// Three figures: bags, coffee on hand, and the days it lasts.
private struct BacklogFigures: View {
    let summary: BacklogSummary

    var body: some View {
        let bags = summary.queuedBags + summary.frozenBags
        HStack(spacing: 10) {
            figure("\(bags)", bags == 1 ? "bag" : "bags", note: summary.frozenBags > 0 ? "\(summary.frozenBags) frozen" : nil)
            figure(Self.weight(summary.grams), "on hand", note: nil)
            figure(
                "\(summary.coffeeDays ?? 0)", summary.coffeeDays == 1 ? "day of coffee" : "days of coffee",
                note: summary.lastCoffeeDay.map { "through \(Format.shortDay($0))" } ?? "none ready")
        }
    }

    /// "850 g", or "1.8 kg" from a kilo up.
    static func weight(_ grams: Double) -> String {
        grams >= 1000 ? String(format: "%.1f kg", grams / 1000) : "\(Format.grams(grams.rounded())) g"
    }

    private func figure(_ value: String, _ label: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.title2.bold())
                .monospacedDigit()
                .foregroundStyle(Theme.accent)
            Text(label).font(.caption.weight(.semibold))
            Text(note ?? " ").font(.caption2).foregroundStyle(Theme.text2)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
    }
}

/// The share button for the Beans screen: the usual arrow out of a box.
struct ShareBeansLink: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ShareLink(item: BeansSnapshot(model: model), preview: SharePreview("Coffee backlog")) {
            Image(systemName: "square.and.arrow.up")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share the beans")
    }
}
