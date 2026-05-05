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

    // Settings — tabs
    case settingsGeneral
    case settingsNotifications
    case settingsAbout

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

        .settingsGeneral: "General",
        .settingsNotifications: "Notifications",
        .settingsAbout: "About",

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

        .settingsGeneral: "通用",
        .settingsNotifications: "通知",
        .settingsAbout: "关于",

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
