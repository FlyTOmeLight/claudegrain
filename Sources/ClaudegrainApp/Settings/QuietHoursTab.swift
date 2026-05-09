import SwiftUI
import ClaudegrainCore

/// Settings tab for Quiet Hours (ADR-0009).
///
/// - Toggle to enable/disable the suppression window.
/// - Two `DatePicker`s for start/end (hour+minute, device-local).
/// - Window may span midnight; cross-midnight semantics live in
///   `QuietHours.contains`.
struct QuietHoursTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var current: QuietHours = .default

    var body: some View {
        Form {
            Section {
                Toggle(model.t(.quietHoursEnable), isOn: bindEnabled)
            }

            Section {
                LabeledContent(model.t(.quietHoursFrom)) {
                    DatePicker("", selection: bindStart, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                LabeledContent(model.t(.quietHoursTo)) {
                    DatePicker("", selection: bindEnd, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
            .disabled(!current.enabled)

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(model.t(.quietHoursDeviceLocal), systemImage: "clock")
                    Text(model.t(.quietHoursDescription))
                }
                .font(.callout)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { current = model.preferences.quietHours }
    }

    private var bindEnabled: Binding<Bool> {
        Binding(
            get: { current.enabled },
            set: { current.enabled = $0; model.preferences.quietHours = current }
        )
    }

    private var bindStart: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: current.startHour,
                    minute: current.startMinute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { d in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: d)
                current.startHour = comps.hour ?? 0
                current.startMinute = comps.minute ?? 0
                model.preferences.quietHours = current
            }
        )
    }

    private var bindEnd: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: current.endHour,
                    minute: current.endMinute,
                    second: 0,
                    of: Date()
                ) ?? Date()
            },
            set: { d in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: d)
                current.endHour = comps.hour ?? 0
                current.endMinute = comps.minute ?? 0
                model.preferences.quietHours = current
            }
        )
    }
}
