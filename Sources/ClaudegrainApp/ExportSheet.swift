import SwiftUI
import AppKit
import ClaudegrainCore
import UniformTypeIdentifiers

@MainActor
final class ExportSheetCoordinator: ObservableObject {
    @Published var range: RangePreset = .last7d
    @Published var dimension: ExportDimension = .perRepoDaily
    @Published var format: ExportFormat = .csv
    @Published var status: String?

    private let exporter: EventsExporter
    init(exporter: EventsExporter) { self.exporter = exporter }

    enum RangePreset: String, CaseIterable, Identifiable {
        case today, last7d, last30d, thisWeek, lastWeek
        var id: String { rawValue }
        func interval(now: Date = Date()) -> DateInterval {
            let cal = Calendar.current
            switch self {
            case .today:    return DateInterval(start: cal.startOfDay(for: now), end: now)
            case .last7d:   return DateInterval(start: now.addingTimeInterval(-7 * 86_400), end: now)
            case .last30d:  return DateInterval(start: now.addingTimeInterval(-30 * 86_400), end: now)
            case .thisWeek: return DateInterval(start: WeekDelta.mondayUTC(of: now), end: now)
            case .lastWeek:
                let thisStart = WeekDelta.mondayUTC(of: now)
                let lastStart = thisStart.addingTimeInterval(-7 * 86_400)
                return DateInterval(start: lastStart, end: thisStart)
            }
        }
    }

    func runExport() async {
        let panel = NSSavePanel()
        panel.allowedContentTypes = format == .csv
            ? [UTType.commaSeparatedText]
            : [UTType.json]
        panel.nameFieldStringValue = "claudegrain-\(suggestedName()).\(format.rawValue)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try await exporter.export(
                range: range.interval(),
                dimension: dimension,
                format: format,
                to: url
            )
            status = "Saved to \(url.lastPathComponent)"
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            status = "Export failed: \(error.localizedDescription)"
        }
    }

    private func suggestedName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        return "\(f.string(from: Date()))-\(dimension.rawValue.replacingOccurrences(of: " ", with: "-"))"
    }
}

struct ExportSheet: View {
    @StateObject var coord: ExportSheetCoordinator
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.t(.exportSheetTitle))
                .font(.headline)

            HStack {
                Text(model.t(.exportRangeLabel))
                    .frame(width: 80, alignment: .trailing)
                Picker("", selection: $coord.range) {
                    Text(model.t(.exportRangeToday)).tag(ExportSheetCoordinator.RangePreset.today)
                    Text(model.t(.exportRangeLast7d)).tag(ExportSheetCoordinator.RangePreset.last7d)
                    Text(model.t(.exportRangeLast30d)).tag(ExportSheetCoordinator.RangePreset.last30d)
                    Text(model.t(.exportRangeThisWeek)).tag(ExportSheetCoordinator.RangePreset.thisWeek)
                    Text(model.t(.exportRangeLastWeek)).tag(ExportSheetCoordinator.RangePreset.lastWeek)
                }
                .labelsHidden()
            }

            HStack {
                Text(model.t(.exportDimensionLabel))
                    .frame(width: 80, alignment: .trailing)
                Picker("", selection: $coord.dimension) {
                    Text(model.t(.exportDimRepoDaily)).tag(ExportDimension.perRepoDaily)
                    Text(model.t(.exportDimToolDaily)).tag(ExportDimension.perToolDaily)
                    Text(model.t(.exportDimModelDaily)).tag(ExportDimension.perModelDaily)
                    Text(model.t(.exportDimRaw)).tag(ExportDimension.rawEvents)
                }
                .labelsHidden()
            }

            HStack {
                Text(model.t(.exportFormatLabel))
                    .frame(width: 80, alignment: .trailing)
                Picker("", selection: $coord.format) {
                    Text("CSV").tag(ExportFormat.csv)
                    Text("JSON").tag(ExportFormat.json)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 200)
            }

            if let status = coord.status {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(model.t(.exportCancel)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(model.t(.exportButton)) {
                    Task { await coord.runExport() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}
