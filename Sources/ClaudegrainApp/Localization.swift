import Foundation

/// Static EN/ZH string tables. Add new keys here as the UI grows.
/// Lookup is via `AppModel.t(.key)` which honors the user's language pref.
enum L: String, Hashable {
    // Header
    case versionTagline             // "v 0.1 · usage · live"
    case statusBoot
    case statusOauth
    case statusJsonl
    case statusCli
    case statusOffline
    case statusLive

    // Hero
    case heroTabTotal
    case heroTabToday
    case heroSubLifetime              // "lifetime · %@k tok"
    case heroSubToday                 // "%@k tok today"
    case heroVsYesterday              // "vs $%.2f yest · %@k tok"

    // Sections
    case sectionUsageLimits
    case sectionSpend7d
    case sectionTopCosts

    // Vitals
    case vitalSession
    case vitalWeekly
    case vitalCache
    case cacheBaseline                // "↑ %d%% hit · vs P50"

    // Subtotals
    case subtotalShown                // "SHOWN · TOP %d REPOS"
    case subtotalOther                // "OTHER REPOS"
    case subtotalCacheBreakdown       // "CACHE SAVINGS BREAKDOWN"
    case cacheReadHits                // "Read · cache hits"
    case cacheWriteCached             // "Write · cached"
    case cacheHitRateBoost            // "Hit rate boost"

    case netToday

    // Footer
    case kbCfg
    case kbRefresh
    case kbQuit
    case footerEndEvents              // "END · %@ EVENTS"

    // v0.2 — forecast badge
    case forecastBlockHits        // "block hits %@"
    case forecastBlockSafe        // "block · safe"
    case forecastWeeklyHits       // "weekly hits %@"
    case forecastConfidenceLow    // "low conf"
    case forecastConfidenceMedium // "medium"
    case forecastConfidenceHigh   // "high"
    case forecastBasisEwma        // "ewma"
    case forecastBasisLinear      // "linear"

    // v0.2 — week delta row
    case weekDeltaLabel           // "Δ vs last week"
    case weekDeltaPctUp           // "+%d%% · cache %@"
    case weekDeltaPctDown         // "%d%% · cache %@"  (negative pct)
    case weekDeltaCacheUp         // "+%d pp"
    case weekDeltaCacheDown       // "%d pp"
    case weekDeltaFirstWeek       // "first week"

    // v0.2 — model mix
    case modelMixLabel            // "MODELS"
    case modelMixOpus             // "opus"
    case modelMixSonnet           // "sonnet"
    case modelMixHaiku            // "haiku"
    case modelMixUnknown          // "other"

    // v0.2 — export
    case exportMenuItem           // "Export Usage…"
    case exportSheetTitle         // "Export usage data"
    case exportRangeLabel         // "Range"
    case exportRangeToday
    case exportRangeLast7d
    case exportRangeLast30d
    case exportRangeThisWeek
    case exportRangeLastWeek
    case exportRangeCustom
    case exportDimensionLabel
    case exportDimRepoDaily
    case exportDimToolDaily
    case exportDimModelDaily
    case exportDimRaw
    case exportFormatLabel
    case exportButton             // "Export…"
    case exportCancel             // "Cancel"
    case exportDone               // "Saved to %@"

    // v0.2 — kbd
    case kbExport                 // "export"

    // Settings — tabs
    case settingsGeneral
    case settingsNotifications
    case settingsAbout
    case settingsBudgets
    case settingsQuietHours

    // Settings — quiet hours
    case quietHoursEnable
    case quietHoursFrom
    case quietHoursTo
    case quietHoursDeviceLocal
    case quietHoursDescription

    // Settings — budgets
    case budgetsGlobalSection
    case budgetsGlobalDaily
    case budgetsRepoSection
    case budgetsAddSection
    case budgetsAddRepoPlaceholder
    case budgetsAddButton
    case budgetsEmpty

    // Settings — general
    case sgMenuBarShows
    case sgSessionPct
    case sgWeeklyPct
    case sgTodayCost
    case sgCacheHit
    case sgOpenAtLogin
    case sgLanguage
    case sgLanguageEnglish
    case sgLanguageChinese
    case sgLayout
    case sgLayoutScroll
    case sgLayoutFixed

    // Settings — notifications
    case snTriggers
    case snThreshold
    case snBurnRate
    case snBlockReset
    case snRepoOverspend
    case snSound
    case snSoundDefault
    case snSoundGlass
    case snSoundPing
    case snImportSound

    // Settings — about
    case saTagline
    case saMit
    case saViewSource
}

enum L10n {
    static func tr(_ key: L, _ language: AppLanguage) -> String {
        switch language {
        case .english: return en[key] ?? key.rawValue
        case .chinese: return zh[key] ?? en[key] ?? key.rawValue
        }
    }

    private static let en: [L: String] = [
        .versionTagline: "v 0.1 · usage · live",
        .statusBoot: "BOOT",
        .statusOauth: "OAUTH ✓",
        .statusJsonl: "JSONL",
        .statusCli: "CLI",
        .statusOffline: "OFFLINE",
        .statusLive: "LIVE",

        .heroTabTotal: "TOTAL",
        .heroTabToday: "TODAY",
        .heroSubLifetime: "lifetime · %@k tok",
        .heroSubToday: "%@k tok today",
        .heroVsYesterday: "vs $%.2f yest · %@k tok",

        .sectionUsageLimits: "USAGE LIMITS",
        .sectionSpend7d: "7d SPEND · LINE",
        .sectionTopCosts: "TOP COSTS · 7d trend",

        .vitalSession: "SESSION",
        .vitalWeekly: "WEEKLY",
        .vitalCache: "CACHE",
        .cacheBaseline: "↑ %d%% hit · vs P50",

        .subtotalShown: "SHOWN · TOP %d REPOS",
        .subtotalOther: "OTHER REPOS",
        .subtotalCacheBreakdown: "CACHE SAVINGS BREAKDOWN",
        .cacheReadHits: "Read · cache hits",
        .cacheWriteCached: "Write · cached",
        .cacheHitRateBoost: "Hit rate boost",

        .netToday: "NET TODAY",

        .kbCfg: "cfg",
        .kbRefresh: "refresh",
        .kbQuit: "quit",
        .footerEndEvents: "END · %@ EVENTS",

        .forecastBlockHits:        "block hits %@",
        .forecastBlockSafe:        "block · safe",
        .forecastWeeklyHits:       "weekly hits %@",
        .forecastConfidenceLow:    "low conf",
        .forecastConfidenceMedium: "medium",
        .forecastConfidenceHigh:   "high",
        .forecastBasisEwma:        "ewma",
        .forecastBasisLinear:      "linear",
        .weekDeltaLabel:           "Δ vs last week",
        .weekDeltaPctUp:           "+%d%% · cache %@",
        .weekDeltaPctDown:         "%d%% · cache %@",
        .weekDeltaCacheUp:         "+%d pp",
        .weekDeltaCacheDown:       "%d pp",
        .weekDeltaFirstWeek:       "first week",
        .modelMixLabel:            "MODELS",
        .modelMixOpus:             "opus",
        .modelMixSonnet:           "sonnet",
        .modelMixHaiku:            "haiku",
        .modelMixUnknown:          "other",
        .exportMenuItem:           "Export Usage…",
        .exportSheetTitle:         "Export usage data",
        .exportRangeLabel:         "Range",
        .exportRangeToday:         "Today",
        .exportRangeLast7d:        "Last 7 days",
        .exportRangeLast30d:       "Last 30 days",
        .exportRangeThisWeek:      "This week",
        .exportRangeLastWeek:      "Last week",
        .exportRangeCustom:        "Custom…",
        .exportDimensionLabel:     "Dimension",
        .exportDimRepoDaily:       "Per-repo · daily",
        .exportDimToolDaily:       "Per-tool · daily",
        .exportDimModelDaily:      "Per-model · daily",
        .exportDimRaw:             "Raw events",
        .exportFormatLabel:        "Format",
        .exportButton:             "Export…",
        .exportCancel:             "Cancel",
        .exportDone:               "Saved to %@",
        .kbExport:                 "export",

        .settingsGeneral: "General",
        .settingsNotifications: "Notifications",
        .settingsAbout: "About",
        .settingsBudgets:           "Budgets",
        .settingsQuietHours:        "Quiet Hours",
        .quietHoursEnable:          "Enable quiet hours",
        .quietHoursFrom:            "From",
        .quietHoursTo:              "To",
        .quietHoursDeviceLocal:     "Time zone: device local",
        .quietHoursDescription:     "Notifications during this window are suppressed. The menu bar icon and popover still update.",
        .budgetsGlobalSection:      "Global default",
        .budgetsGlobalDaily:        "Daily $",
        .budgetsRepoSection:        "Per-repo overrides",
        .budgetsAddSection:         "Add repo budget",
        .budgetsAddRepoPlaceholder: "Repo path or alias",
        .budgetsAddButton:          "Add",
        .budgetsEmpty:              "No per-repo budgets yet.",

        .sgMenuBarShows: "Menu bar shows",
        .sgSessionPct: "Session %",
        .sgWeeklyPct: "Weekly %",
        .sgTodayCost: "Today $",
        .sgCacheHit: "Cache hit %",
        .sgOpenAtLogin: "Open at login",
        .sgLanguage: "Language",
        .sgLanguageEnglish: "English",
        .sgLanguageChinese: "中文",
        .sgLayout: "Layout",
        .sgLayoutScroll: "Scrollable",
        .sgLayoutFixed: "Fixed (no scroll)",

        .snTriggers: "Triggers",
        .snThreshold: "Threshold alerts (session 70/90% · weekly 85%)",
        .snBurnRate: "Burn-rate spikes (over P90 × 2)",
        .snBlockReset: "Block reset (10 min before)",
        .snRepoOverspend: "Per-repo overspend",
        .snSound: "Sound",
        .snSoundDefault: "claudegrain default",
        .snSoundGlass: "Glass (system)",
        .snSoundPing: "Ping (system)",
        .snImportSound: "Import sound file…",

        .saTagline: "Granular Claude Code usage in your menu bar.",
        .saMit: "MIT licensed · open source",
        .saViewSource: "View source on GitHub",
    ]

    private static let zh: [L: String] = [
        .versionTagline: "v 0.1 · 用量 · 实时",
        .statusBoot: "启动中",
        .statusOauth: "OAUTH ✓",
        .statusJsonl: "JSONL",
        .statusCli: "CLI",
        .statusOffline: "离线",
        .statusLive: "在线",

        .heroTabTotal: "累计",
        .heroTabToday: "今日",
        .heroSubLifetime: "累计 · %@k tok",
        .heroSubToday: "今日 %@k tok",
        .heroVsYesterday: "昨日 $%.2f · 今日 %@k tok",

        .sectionUsageLimits: "用量限额",
        .sectionSpend7d: "7 日花费 · 折线",
        .sectionTopCosts: "Top 仓库 · 7 日趋势",

        .vitalSession: "本次会话",
        .vitalWeekly: "本周",
        .vitalCache: "缓存",
        .cacheBaseline: "↑ %d%% 命中 · vs P50",

        .subtotalShown: "展示 · Top %d 仓库",
        .subtotalOther: "其他仓库",
        .subtotalCacheBreakdown: "缓存节省明细",
        .cacheReadHits: "Read · 缓存命中",
        .cacheWriteCached: "Write · 已缓存",
        .cacheHitRateBoost: "命中率增益",

        .netToday: "今日净花费",

        .kbCfg: "设置",
        .kbRefresh: "刷新",
        .kbQuit: "退出",
        .footerEndEvents: "END · %@ 条事件",

        .forecastBlockHits:        "块预计 %@ 触顶",
        .forecastBlockSafe:        "块 · 安全",
        .forecastWeeklyHits:       "本周预计 %@ 触顶",
        .forecastConfidenceLow:    "低信心",
        .forecastConfidenceMedium: "中等",
        .forecastConfidenceHigh:   "高信心",
        .forecastBasisEwma:        "EWMA",
        .forecastBasisLinear:      "线性",
        .weekDeltaLabel:           "Δ 对比上周",
        .weekDeltaPctUp:           "+%d%% · 缓存 %@",
        .weekDeltaPctDown:         "%d%% · 缓存 %@",
        .weekDeltaCacheUp:         "+%d pp",
        .weekDeltaCacheDown:       "%d pp",
        .weekDeltaFirstWeek:       "首周",
        .modelMixLabel:            "模型分布",
        .modelMixOpus:             "opus",
        .modelMixSonnet:           "sonnet",
        .modelMixHaiku:            "haiku",
        .modelMixUnknown:          "其他",
        .exportMenuItem:           "导出用量…",
        .exportSheetTitle:         "导出用量数据",
        .exportRangeLabel:         "时间范围",
        .exportRangeToday:         "今日",
        .exportRangeLast7d:        "近 7 天",
        .exportRangeLast30d:       "近 30 天",
        .exportRangeThisWeek:      "本周",
        .exportRangeLastWeek:      "上周",
        .exportRangeCustom:        "自定义…",
        .exportDimensionLabel:     "维度",
        .exportDimRepoDaily:       "按仓库 · 日",
        .exportDimToolDaily:       "按工具 · 日",
        .exportDimModelDaily:      "按模型 · 日",
        .exportDimRaw:             "原始事件",
        .exportFormatLabel:        "格式",
        .exportButton:             "导出…",
        .exportCancel:             "取消",
        .exportDone:               "已保存到 %@",
        .kbExport:                 "导出",

        .settingsGeneral: "通用",
        .settingsNotifications: "通知",
        .settingsAbout: "关于",
        .settingsBudgets:           "预算",
        .settingsQuietHours:        "免打扰",
        .quietHoursEnable:          "启用免打扰时段",
        .quietHoursFrom:            "从",
        .quietHoursTo:              "到",
        .quietHoursDeviceLocal:     "时区:本机本地",
        .quietHoursDescription:     "时段内不投递通知。菜单栏图标和 popover 仍会更新。",
        .budgetsGlobalSection:      "全局默认",
        .budgetsGlobalDaily:        "日预算 $",
        .budgetsRepoSection:        "按仓库覆盖",
        .budgetsAddSection:         "添加仓库预算",
        .budgetsAddRepoPlaceholder: "仓库路径或别名",
        .budgetsAddButton:          "添加",
        .budgetsEmpty:              "暂无单仓库预算。",

        .sgMenuBarShows: "菜单栏显示",
        .sgSessionPct: "会话 %",
        .sgWeeklyPct: "本周 %",
        .sgTodayCost: "今日 $",
        .sgCacheHit: "缓存命中 %",
        .sgOpenAtLogin: "登录时启动",
        .sgLanguage: "语言",
        .sgLanguageEnglish: "English",
        .sgLanguageChinese: "中文",
        .sgLayout: "布局",
        .sgLayoutScroll: "可滚动",
        .sgLayoutFixed: "定屏(不滚动)",

        .snTriggers: "触发条件",
        .snThreshold: "阈值告警 (会话 70/90% · 本周 85%)",
        .snBurnRate: "燃烧率突增 (超 P90 × 2)",
        .snBlockReset: "块重置前 10 分钟提醒",
        .snRepoOverspend: "单仓库超额",
        .snSound: "提示音",
        .snSoundDefault: "claudegrain 默认",
        .snSoundGlass: "Glass (系统)",
        .snSoundPing: "Ping (系统)",
        .snImportSound: "导入声音文件…",

        .saTagline: "菜单栏中的 Claude Code 用量监控。",
        .saMit: "MIT 许可 · 开源",
        .saViewSource: "在 GitHub 查看源码",
    ]
}
