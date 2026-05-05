import SwiftUI
import ClaudegrainCore

/// One-liner: "MODELS · opus 64% · sonnet 31% · haiku 5%"
/// Hidden when modelMix is empty.
struct ModelMixRow: View {
    let mix: [ModelFamily: Double]
    @Environment(\.theme) private var theme
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if !mix.isEmpty {
            HStack(spacing: 8) {
                Text(model.t(.modelMixLabel))
                    .font(.cgMonoXSmall)
                    .tracking(1.6)
                    .foregroundStyle(theme.ink.opacity(0.55))
                Text(mixDescription)
                    .font(.cgMonoSmall)
                    .foregroundStyle(theme.inkBold.opacity(0.85))
                Spacer()
            }
        } else {
            EmptyView()
        }
    }

    private var mixDescription: String {
        let order: [ModelFamily] = [.opus, .sonnet, .haiku, .unknown]
        let parts = order.compactMap { fam -> String? in
            guard let pct = mix[fam], pct > 0.005 else { return nil }
            let pctInt = Int((pct * 100).rounded())
            let label: String
            switch fam {
            case .opus:    label = model.t(.modelMixOpus)
            case .sonnet:  label = model.t(.modelMixSonnet)
            case .haiku:   label = model.t(.modelMixHaiku)
            case .unknown: label = model.t(.modelMixUnknown)
            }
            return "\(label) \(pctInt)%"
        }
        return parts.joined(separator: " · ")
    }
}
