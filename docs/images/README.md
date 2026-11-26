# Image Index

This index lists the assets in `docs/images` and where each one is used. The GitHub Pages site in `site/` keeps its own copies under `site/docs/images` and `site/docs/media`; changing a file here does not change the website.

## Root README

| File | Content | Used in |
|---|---|---|
| `readme-wordmark.svg` | Neon Vision Editor wordmark (set in `space-grotesk-700.ttf`) | README header |
| `readme-hero-accent.svg` | Accent line under the wordmark | README header |
| `NeonVisionEditorIcon.png` | App icon | README header |
| `readme-hero-macos-light.png` | macOS light editor with toolbar, tabs, status bar, and code minimap | README hero; CHANGELOG v1.2.0 |
| `mac-light-editor-sidebar.png` | macOS light editor with symbol sidebar | README `Platform Gallery` > `macOS` |
| `mac-light-editor-wide.png` | macOS wide light editor with toolbar actions | README `Platform Gallery` > `macOS` |
| `mac-light-editor-compact.png` | macOS compact light editor | README `Platform Gallery` > `macOS` |
| `mac-light-editor-minimap.png` | macOS light editor with code minimap | README `Platform Gallery` > `macOS` |
| `readme-ipad-project-dark.png` | iPad editor beside the project file browser, dark | README `Platform Gallery` > `iPad` |
| `readme-ipad-markdown-preview-dark.png` | iPad Markdown source and preview side by side, dark | README `Platform Gallery` > `iPad` |
| `readme-iphone-editor-dark.png` | iPhone Swift editor with bottom toolbar, dark | README `Platform Gallery` > `iPhone` |
| `readme-iphone-editor-light.png` | iPhone Swift editor with bottom toolbar, light | README `Platform Gallery` > `iPhone` |
| `readme-iphone-minimap-dark.png` | iPhone editor with code minimap, dark | README `Platform Gallery` > `iPhone` |
| `readme-iphone-project-dark.png` | iPhone project file browser, dark | README `Platform Gallery` > `iPhone` |
| `architecture-at-a-glance.svg` | Ownership and data-flow diagram | README `Architecture At A Glance`; `docs/ARCHITECTURE.md` |

## Generated charts

| File | Source | Used in |
|---|---|---|
| `release-download-trend-light.svg` | `scripts/update_download_metrics.py` | README `Download Metrics` (light and default) |
| `release-download-trend-dark.svg` | `scripts/update_download_metrics.py` | README `Download Metrics` (dark) |
| `release-download-trend.svg` | `scripts/update_download_metrics.py` | Backward-compatible dark copy for old links |
| `neon-vision-release-history-0.1-to-0.5.svg` | `scripts/update_release_history_svg.py` | Regenerated during release preparation; not embedded in the README |
| `neon-vision-release-history-0.1-to-0.5-light.svg` | `scripts/update_release_history_svg.py` | Regenerated during release preparation; not embedded in the README |

## Historical screenshots

These files are kept for older CHANGELOG entries and as source material. The README no longer embeds them; the website uses its own copies.

| File | Content | Referenced by |
|---|---|---|
| `ipad-editor-light.png` | iPad editor, light | CHANGELOG v0.5.4 |
| `iphone-themes-light-frame.png` | Framed iPhone theme editor, light | CHANGELOG v0.5.6 |
| `ipad-editor-dark.png` | iPad editor, dark | Not referenced (website copy in `site/docs/images`) |
| `iphone-editor-light-frame-updated.png` | Framed iPhone editor with accessory bar, light | Not referenced |
| `iphone-menu-dark-frame.png` | Framed iPhone editor with overflow menu, dark | Not referenced |
| `iphone-markdown-preview-dark.png` | iPhone Markdown preview sheet, dark | Not referenced |
| `ai-assistant-macos.png`, `ai-assistant-iphone.png` | AI assistant on macOS and iPhone | Not referenced (website copies in `site/docs/images`) |
| `profile-neon-editor-light.png`, `profile-neon-workspace.png`, `profile-neon-markdown-preview.png` | Screenshots from the public h3pdesign GitHub profile | Not referenced (website copies in `site/docs/images`) |
| `neon-workflows-hero-20260723.png` | Marketing header in a MacBook frame | Not referenced |

## Notes

- App Store screenshots are managed in App Store Connect; local copies live in `docs/media/app-store`.
- `docs/media` holds the responsive website images (`.avif`, `.webp`) and social card; the deployed website serves its copies from `site/docs/media`.
- Keep this index updated when adding, renaming, or retiring an image.
