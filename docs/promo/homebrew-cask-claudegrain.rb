# Homebrew Cask formula for claudegrain
#
# Submission target: https://github.com/Homebrew/homebrew-cask/tree/master/Casks/c
# Filename in that repo: Casks/c/claudegrain.rb
#
# Local validation before PR:
#   brew install --cask --no-quarantine ./docs/promo/homebrew-cask-claudegrain.rb
#   brew audit --cask --new ./docs/promo/homebrew-cask-claudegrain.rb
#   brew style --cask ./docs/promo/homebrew-cask-claudegrain.rb
#
# After every release:
#   1. Run `shasum -a 256 dist/claudegrain-*.dmg` (or fetch from gh release).
#   2. Update version + sha256 below.
#   3. Bump in homebrew-cask repo via PR (or use `brew bump-cask-pr claudegrain`).

cask "claudegrain" do
  version "1.0.1"
  sha256 "d90d786823aa02223d86ab36a6058b367d2a0468030e5dd40f6d3bdf24eec66a"

  url "https://github.com/FlyTOmeLight/claudegrain/releases/download/v#{version}/claudegrain-#{version}.dmg"
  name "claudegrain"
  desc "Granular Claude Code usage in your menu bar — per-repo, per-tool, per-MCP attribution"
  homepage "https://github.com/FlyTOmeLight/claudegrain"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates false
  depends_on macos: ">= :sonoma"

  app "claudegrain.app"

  zap trash: [
    "~/Library/Application Support/claudegrain",
    "~/Library/Preferences/dev.claudegrain.menubar.plist",
    "~/Library/Caches/dev.claudegrain.menubar",
  ]
end
