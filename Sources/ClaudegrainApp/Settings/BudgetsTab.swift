import SwiftUI
import ClaudegrainCore

/// Settings tab for per-repo budgets (ADR-0008).
///
/// - Global default daily $ — applied to any repo without an explicit override.
/// - Per-repo overrides — daily and/or weekly ceilings, listed in a Form.
/// - Add — quick row to register a new repo budget (path or alias).
struct BudgetsTab: View {
    @ObservedObject var budgets: BudgetStore
    let recentRepos: [String]
    @EnvironmentObject private var model: AppModel
    @State private var newRepo: String = ""
    @State private var newDaily: String = ""
    @State private var newWeekly: String = ""

    var body: some View {
        Form {
            Section(model.t(.budgetsGlobalSection)) {
                LabeledContent(model.t(.budgetsGlobalDaily)) {
                    TextField("$", value: Binding(
                        get: { budgets.globalDefaultDailyUSD },
                        set: { budgets.globalDefaultDailyUSD = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section {
                if sortedRepoKeys.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(model.t(.budgetsEmpty))
                            .foregroundStyle(.secondary)
                        Text(model.t(.budgetsEmptyHint))
                            .font(.callout)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                } else {
                    BudgetHeaderRow()
                    ForEach(sortedRepoKeys, id: \.self) { repo in
                        BudgetRowView(budgets: budgets, repo: repo)
                    }
                }
            } header: {
                Text(model.t(.budgetsRepoSection))
            }

            Section(model.t(.budgetsAddSection)) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField(model.t(.budgetsAddRepoPlaceholder), text: $newRepo)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        TextField("daily $", text: $newDaily)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        TextField("weekly $", text: $newWeekly)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Spacer()
                        Button(model.t(.budgetsAddButton)) {
                            let trimmed = newRepo.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            budgets.setBudget(
                                repo: trimmed,
                                daily: Double(newDaily),
                                weekly: Double(newWeekly)
                            )
                            newRepo = ""; newDaily = ""; newWeekly = ""
                        }
                        .disabled(newRepo.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    /// Configured repos plus any recent (auto-discovered) ones, deduped + sorted.
    private var sortedRepoKeys: [String] {
        let configured = Set(budgets.allBudgets.keys)
        let union = configured.union(recentRepos)
        return union.sorted()
    }
}

/// Column header for the per-repo budget table.
private struct BudgetHeaderRow: View {
    var body: some View {
        HStack {
            Text("Repo")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Daily")
                .frame(width: 90, alignment: .trailing)
            Text("Weekly")
                .frame(width: 90, alignment: .trailing)
            Spacer().frame(width: 24)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

/// One row per repo. Edits write through `BudgetStore.setBudget`.
/// Configured rows show explicit values; unconfigured rows show
/// the global default as TextField prompt so the user can tell at
/// a glance which repos are using the override vs. inheriting.
private struct BudgetRowView: View {
    @ObservedObject var budgets: BudgetStore
    let repo: String

    private var isConfigured: Bool { budgets.allBudgets[repo] != nil }

    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(isConfigured ? Color.accentColor : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
                Text(repo)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(repo)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField(
                "",
                value: dailyBinding,
                format: .number.precision(.fractionLength(2)),
                prompt: Text(String(format: "%.2f", budgets.globalDefaultDailyUSD))
                    .foregroundStyle(.tertiary)
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 90)
            .multilineTextAlignment(.trailing)

            TextField(
                "",
                value: weeklyBinding,
                format: .number.precision(.fractionLength(2)),
                prompt: Text("—").foregroundStyle(.tertiary)
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 90)
            .multilineTextAlignment(.trailing)

            Button(role: .destructive) {
                budgets.removeBudget(repo: repo)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .disabled(!isConfigured)
            .help(isConfigured ? "Remove override" : "No override to remove")
        }
    }

    private var dailyBinding: Binding<Double?> {
        Binding(
            get: { budgets.allBudgets[repo]?.dailyUSD },
            set: { newValue in
                budgets.setBudget(
                    repo: repo,
                    daily: newValue,
                    weekly: budgets.allBudgets[repo]?.weeklyUSD
                )
            }
        )
    }

    private var weeklyBinding: Binding<Double?> {
        Binding(
            get: { budgets.allBudgets[repo]?.weeklyUSD },
            set: { newValue in
                budgets.setBudget(
                    repo: repo,
                    daily: budgets.allBudgets[repo]?.dailyUSD,
                    weekly: newValue
                )
            }
        )
    }
}
