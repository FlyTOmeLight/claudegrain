# Recording the README demo gif

## Tools

- [Kap](https://getkap.co) — open source, free, fixed-aspect captures, gif export
  built in. Install: `brew install --cask kap`.
- Alternative: [Gifox](https://apps.apple.com/app/gifox-2-gif-recorder-editor/id1461845568)
  if you want trimming / timeline UI.

## Capture

1. Quit / kill any running claudegrain so the menu-bar item is fresh.
2. `open /Applications/claudegrain.app` and wait for ingest to finish (≤30s).
3. Open Kap. Drag the capture region to a 720×640 box that frames the menu bar
   icon plus enough room for the popover that drops below it. (The popover
   is 340pt wide; you only need ~360pt of horizontal capture space.)
4. Set FPS to 24, stop on click count = 1.
5. Hit record, then:
   - 0–1s: cursor idle next to the menu icon
   - 1–2s: click icon → popover opens
   - 2–10s: linger 1.5s on each section: total/today tabs, vital limits, 7d chart, top repos, top tools, footer
   - 10–11s: click outside to dismiss
6. Stop. Trim deadweight at start/end. Export as `.gif`. Target ≤4 MB
   (GitHub renders gifs >5MB as inline-link, not embedded).

## Place in repo

```
docs/screenshots/v18-demo.gif        ← the recorded gif
```

Reference from README.md and README.zh-CN.md, replacing the static screenshot
table at the top:

```markdown
![claudegrain demo](docs/screenshots/v18-demo.gif)
```

Keep the dark/light table further down for thumbnails.

## Compression

If the gif is too large:

```bash
brew install gifsicle
gifsicle -O3 --colors=128 docs/screenshots/v18-demo.gif \
  -o docs/screenshots/v18-demo.gif
```

Cuts the file size 30–50% with negligible quality loss.

## Caveat

Don't rerecord on every release — gifs get diff-noise that bloats the repo.
Bake one good demo, replace only when the popover layout meaningfully changes.
