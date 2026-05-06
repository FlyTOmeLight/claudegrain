import SwiftUI
import ClaudegrainCore

struct CommitmentsSheet: View {
    @ObservedObject var log: CommitmentLog
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(model.t(.commitmentsTitle))
                .font(.headline)
            if log.entries.isEmpty {
                Text(model.t(.commitmentsEmpty))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                List(log.entries.reversed()) { c in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(c.repo).bold()
                            Text(formatTime(c.triggeredAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(statusLabel(c.status))
                            .font(.caption)
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(statusColor(c.status).opacity(0.2))
                            .clipShape(Capsule())
                    }
                }
                .listStyle(.bordered)
                .frame(minHeight: 240)
            }
            HStack {
                Spacer()
                Button(model.t(.commitmentsClose)) { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(20).frame(width: 460, height: 360)
    }

    private func formatTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f.string(from: date)
    }

    private func statusLabel(_ s: Commitment.Status) -> String {
        switch s {
        case .open:         return model.t(.commitmentsStatusOpen)
        case .markedPaused: return model.t(.commitmentsStatusPaused)
        case .ignored:      return model.t(.commitmentsStatusIgnored)
        }
    }

    private func statusColor(_ s: Commitment.Status) -> Color {
        switch s {
        case .open:         return .yellow
        case .markedPaused: return .green
        case .ignored:      return .gray
        }
    }
}
