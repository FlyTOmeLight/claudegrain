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
                HStack {
                    Text(model.t(.budgetsGlobalDaily))
                    Spacer()
                    TextField("$", value: Binding(
                        get: { budgets.globalDefaultDailyUSD },
                        set: { budgets.globalDefaultDailyUSD = $0 }
                    ), format: .number.precision(.fractionLength(2)))
                        .frame(width: 80)
                        .multilineTextAlignment(.trailing)
                }
            }

            Section(model.t(.budgetsRepoSection)) {
                if budgets.allBudgets.isEmpty && recentRepos.isEmpty {
                    Text(model.t(.budgetsEmpty))
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedRepoKeys, id: \.self) { repo in
                    BudgetRowView(budgets: budgets, repo: repo)
                }
            }

            Section(model.t(.budgetsAddSection)) {
                HStack {
                    TextField(model.t(.budgetsAddRepoPlaceholder), text: $newRepo)
                    TextField("daily $", text: $newDaily).frame(width: 80)
                    TextField("weekly $", text: $newWeekly).frame(width: 80)
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

/// One row per repo. Edits write through `BudgetStore.setBudget`.
private struct BudgetRowView: View {
    @ObservedObject var budgets: BudgetStore
    let repo: String

    var body: some View {
        HStack {
            Text(repo)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
            TextField("daily", value: dailyBinding,
                      format: .number.precision(.fractionLength(2)))
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
            TextField("weekly", value: weeklyBinding,
                      format: .number.precision(.fractionLength(2)))
                .frame(width: 80)
                .multilineTextAlignment(.trailing)
            Button(role: .destructive) {
                budgets.removeBudget(repo: repo)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private var dailyBinding: Binding<Double> {
        Binding(
            get: {
                budgets.allBudgets[repo]?.dailyUSD
                    ?? budgets.globalDefaultDailyUSD
            },
            set: { newValue in
                budgets.setBudget(
                    repo: repo,
                    daily: newValue,
                    weekly: budgets.allBudgets[repo]?.weeklyUSD
                )
            }
        )
    }

    private var weeklyBinding: Binding<Double> {
        Binding(
            get: { budgets.allBudgets[repo]?.weeklyUSD ?? 0 },
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
