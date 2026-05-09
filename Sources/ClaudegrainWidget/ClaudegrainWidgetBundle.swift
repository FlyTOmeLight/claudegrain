import WidgetKit
import SwiftUI
import ClaudegrainCore

@main
struct ClaudegrainWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudegrainSpendWidget()
    }
}

struct ClaudegrainSpendWidget: Widget {
    let kind = "dev.claudegrain.menubar.widget.spend"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetSnapshotProvider()) { entry in
            // ClaudegrainEntryView applies the V18 Phosphor background
            // via .containerBackground itself — see ClaudegrainEntryView.swift.
            ClaudegrainEntryView(entry: entry)
        }
        .configurationDisplayName("Claudegrain")
        .description("Live session block + today's spend.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
