# 中文社群推广文案

## V2EX `/macOS` 节点

**标题**:
> [分享创造] claudegrain — 菜单栏里的 Claude Code 细粒度用量监控（按仓库/按工具/按 MCP 分账）

**正文**:

```
做了一个开源 macOS 菜单栏小工具，解决一个我自己天天遇到的痛点：

Claude Code 自带的 /usage 只告诉你"会话用了 30%"，但不告诉你这 30%
是哪个仓库花掉的、哪个工具（Bash/Edit/MCP）最烧 token。我开了 7-8 个
重度项目，月底 quota 透支也搞不清楚谁占大头。

claudegrain 三层数据源做这件事：

1. 从 macOS Keychain 读 OAuth token，调用未公开的 oauth/usage 接口拿
   真实会话/周配额。
2. 直接解析 ~/.claude/projects/**/*.jsonl，按 cwd / 工具 / MCP /
   缓存命中率细分。OAuth 接口不暴露这些维度。
3. 兜底跑 claude /usage 抓 stdout。

技术栈：原生 Swift/SwiftUI，仅依赖 GRDB，~10MB binary。LSUIElement 无
Dock 图标。深色 phosphor + 浅色 thermal paper 两套主题。

GitHub: https://github.com/FlyTOmeLight/claudegrain
DMG 下载: 仓库 Releases 页

MIT 协议，欢迎试用 / 拍砖。
```

## 即刻 / 小红书

**短**（即刻 280 字以内）:
```
菜单栏里的 Claude Code 细粒度用量监控

突然意识到，自己天天用 Claude Code，但根本不知道：
- 哪个项目最烧 token
- Bash / Edit / Write 哪个工具最贵
- 缓存命中率多少（直接影响实际花费）

Anthropic 自带的 /usage 只看总用量。我做了个开源工具按仓库/按工具/
按 MCP 分账。原生 Swift。开源 MIT。

GitHub: FlyTOmeLight/claudegrain（菜单栏小工具）
```

**长**（小红书图文，配 popover 截图 3 张）:
```
🟢 一个开源工具帮你看清 Claude Code 钱花哪了

Claude Code 用了几个月，你能告诉我：
❌ 哪个仓库花得最多？
❌ 哪个工具调用最贵？
❌ 你的缓存命中率多少？

Anthropic 官方只给"会话 30%、周 80%"两个百分比就完事了。

我自己 Pro 升 Max 升 Max20，最后还是搞不清钱花哪。所以做了个 claudegrain：

✅ 按仓库分账（看哪个 project 最烧）
✅ 按工具分账（Bash 还是 Edit 占大头）
✅ 按 MCP server 分账（外部工具贡献）
✅ 缓存命中率（>90% = 你架构好）
✅ 7 日花费图 + 时段热力图 + 周期感知预测

技术细节：
- 原生 Swift，~10MB 体积
- 数据全本地，OAuth token 仅发 anthropic.com
- 受热感打印纸/磷光显示器复古风格美学

链接放评论区～开源 MIT，欢迎拍砖。
```

## X / Twitter

**英文**（150 字符）:
```
Built claudegrain: macOS menu bar app that shows which Claude Code repo / tool / MCP is burning your quota. Per-repo $, cache hit %, 7d chart. Open source.

https://github.com/FlyTOmeLight/claudegrain
```

**中文**（140 字以内）:
```
开源了 claudegrain — 菜单栏里的 Claude Code 用量监控

按仓库分账 / 按工具分账 / 按 MCP 分账 / 缓存命中率 / 7 日花费 / 时段热图

原生 Swift / MIT。/usage 只能看总数，这个能看到底是哪个 repo 最烧 token。

https://github.com/FlyTOmeLight/claudegrain
```

## KOL 候选（X / Twitter）

| 账号 | 受众 | 触达姿势 |
| --- | --- | --- |
| @op7418 | AI 工具中文圈 | 私信链接 + demo gif |
| @indigo11 | 设计师 + AI | 强调视觉风格（phosphor receipt） |
| @lyric5400 | AI 应用开发者 | 强调 ADR 工程严谨度 |
| @goeasywayy | 中文 dev | 强调 Swift native |

不要群发同一文案，每个针对一个突出点。

## 时机

- V2EX：周末上午 9-11 点（HN 同期发酵）
- 即刻：晚 8-10 点（黄金 timeline）
- 小红书：午休 12-13 点 / 晚 21-22 点
- X：周二/周三 美东早 9 点（开发者上线）
