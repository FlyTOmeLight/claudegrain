# claudegrain

> 菜单栏里的 Claude Code 细粒度用量监控 —— 按仓库、按工具、按 MCP、按缓存命中率分账。其它同类工具都做不到。

[English](README.md) · **中文**

<p align="center">
  <img src="docs/screenshots/v18-demo.gif" alt="claudegrain 演示 — 磷光深色 + 热感打印纸浅色" width="380">
</p>

## 与同类工具的差异

| 功能 | claudegrain | ccseva | ClaudeBar | ClaudeUsageBar | claudecodeusage |
| --- | --- | --- | --- | --- | --- |
| 会话块用量 % + 重置时间 | ✓ | ✓ | ✓ | ✓ | ✓ |
| 周配额 | ✓ | 部分支持 | ✓ | ✓ | ✓ |
| **按仓库金额分账** | ✓ | — | — | — | — |
| **按工具 token 分账** | ✓ | — | — | — | — |
| **按 MCP 服务器分账** | ✓ | — | — | — | — |
| **缓存命中率** | ✓ | — | — | — | — |
| 7 日花费折线图 | ✓ | — | — | — | — |
| 时段热力图 | ✓ | — | — | — | — |
| 周期感知预测 | ✓ | — | — | — | — |
| 按仓库预算告警 | ✓ | — | — | — | — |
| 原生 Swift / SwiftUI | ✓ | Electron | ✓ | ✓ | ✓ |

## 数据源（三级回退）

1. **OAuth 通道** —— 从 macOS Keychain 读取 Claude Code OAuth token，调用未公开的 `api.anthropic.com/api/oauth/usage` 接口。零配置，会话和周配额数据为真实值。
2. **JSONL 通道** —— 直接解析 `~/.claude/projects/**/*.jsonl`。所有按仓库 / 按工具 / 按 MCP / 缓存命中的分账都由它驱动（OAuth 接口不暴露这些）。配额耗尽时用 P90 估算回退。
3. **CLI 通道** —— 最后兜底：调用 `claude /usage` 抓取 stdout。只在前两个失败时启用。

详见 [docs/adr/0001-three-tier-data-source.md](docs/adr/0001-three-tier-data-source.md)。

## 安装

从 [GitHub Releases](https://github.com/FlyTOmeLight/claudegrain/releases/latest) 下载最新 DMG。

> **首次打开 —— Gatekeeper 拦路**
>
> 当前发行版用 **ad-hoc 签名**（暂未购买 Apple Developer ID），macOS 首次打开会拒绝。
>
> 1. 把 **claudegrain.app** 拖到 `/Applications/`
> 2. 右键 → **打开** → 确认
> 3. 之后正常打开
>
> 或在终端跑：
> ```sh
> xattr -dr com.apple.quarantine /Applications/claudegrain.app
> open /Applications/claudegrain.app
> ```

需要 macOS 14+（Sonoma）。Apple Silicon 和 Intel 都支持。

### 从源码构建

```bash
git clone https://github.com/FlyTOmeLight/claudegrain
cd claudegrain
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  bash scripts/build-dmg.sh
open dist/claudegrain.app
```

Bundle id 是 `dev.claudegrain.menubar`。详情见 [`scripts/README.md`](scripts/README.md)。

## 隐私

- 所有凭证只在本机。无埋点、无分析。
- OAuth token 仅从 Keychain 读取，仅发往 `api.anthropic.com`。
- JSONL 解析全在本地。
- 完全开源（MIT），代码自审。

## 协议

MIT —— 见 [LICENSE](LICENSE)。
