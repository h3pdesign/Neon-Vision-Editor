# Screenshot Index

This index describes screenshot assets in `docs/images` and where they are used.

## Files

- `macos-main.png`
  - Description: Main editor window on macOS.
  - Used in: Legacy macOS screenshot reference.

- `NeonVisionEditorApp.png` (repo root)
  - Description: Primary macOS app screenshot used in the current README gallery.
  - Used in: Root `README.md` (`1-Minute Demo Flow`, `Screenshot Gallery Index`).

- `iphone-menu.png`
  - Description: iPhone editor screenshot with toolbar overflow menu.
  - Used in: Root `README.md` (`iPhone Gallery`).

- `iphone-themes-light.png`
  - Description: iPhone Themes panel in light mode with transparent background.
  - Used in: Root `README.md` (`iPhone Gallery`).

- `iphone-themes-dark.png`
  - Description: iPhone Themes panel in dark mode with transparent background.
  - Used in: Root `README.md` (`iPhone Gallery`).

- `neon-demo.gif`
  - Description: Short animated loop generated from the three screenshots.
  - Used in: Legacy/demo compatibility fallback.

- `neon-demo-light.gif`
  - Description: Light-mode demo loop with pure white background.
  - Used in: Root `README.md` (`1-Minute Demo Flow`, light-mode source).

- `neon-demo-dark.gif`
  - Description: Dark-mode demo loop with pure black background.
  - Used in: Root `README.md` (`1-Minute Demo Flow`, dark-mode source).

- `neon-demo.mp4`
  - Description: Default demo-flow video (H.264 MP4) for improved quality and smaller payload than GIF.
  - Used in: Root `README.md` (`1-Minute Demo Flow`, default source fallback).

- `neon-demo.webm`
  - Description: Default demo-flow video (VP9 WebM) for modern-browser playback efficiency.
  - Used in: Root `README.md` (`1-Minute Demo Flow`, preferred source).

- `neon-demo-light.mp4`
  - Description: Light-background demo-flow video source used to generate light GIF/web/video variants.
  - Used in: Asset generation pipeline (not directly embedded).

- `neon-demo-dark.mp4`
  - Description: Dark-background demo-flow video source used to generate dark GIF variant.
  - Used in: Asset generation pipeline (not directly embedded).

- `release-download-trend.svg`
  - Description: Generated download/clones chart.
  - Source: `scripts/update_download_metrics.py`.
  - Used in: Root `README.md` (`Download Metrics`).

- `neon-vision-release-history-0.1-to-0.5.svg`
  - Description: Visual release flow timeline from version 0.1 to 0.5 (dark-mode variant).
  - Used in: Root `README.md` (`Release Flow (0.1 to 0.5)`, dark scheme).

- `neon-vision-release-history-0.1-to-0.5-light.svg`
  - Description: Light-mode variant of the release flow timeline from version 0.1 to 0.5.
  - Used in: Root `README.md` (`Release Flow (0.1 to 0.5)`, light/default scheme).

## Notes

- App Store media is managed in App Store Connect and linked from the root `README.md`.
- Keep this index updated when adding or renaming image assets.
