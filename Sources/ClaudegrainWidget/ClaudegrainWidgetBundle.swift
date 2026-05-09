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
            ClaudegrainEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Claudegrain")
        .description("Live session block + today's spend.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
