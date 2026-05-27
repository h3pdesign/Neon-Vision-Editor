# Neon Vision Editor: A Lightweight Native Editor That Is Growing Without Becoming an IDE

There is a specific kind of editor I keep wanting on Apple platforms.

Not a full IDE. Not an Electron workspace. Not a notes app pretending to be a code editor. Just a fast, native place to open a file, inspect it, edit it, compare it, preview it, and move on.

That is the direction behind Neon Vision Editor. The latest release cycle has been focused on making the app feel more complete without losing the lightweight shape that made it useful in the first place.

## The Big Shift: From Simple Editor to Daily Utility

The core idea is still simple: open text and code files quickly across macOS, iPadOS, and iOS.

What changed recently is the surrounding workflow. Neon Vision Editor now feels less like a single text surface and more like a compact editing environment:

- a cleaner project sidebar
- a more useful table of contents sidebar
- a persistent sidebar terminal
- a wider, scroll-synced code minimap
- improved Markdown preview themes
- better syntax highlighting performance
- more reliable large-file behavior
- tighter iPhone and iPad layouts
- a more polished macOS translucent interface
- optional command-line helper guidance
- real Apple Foundation Models routing where system support is available

The goal is not to compete with heavyweight IDEs. The goal is to cover the practical middle: quick edits, Markdown, config files, scripts, JSON, project browsing, diffs, Git awareness, and mobile-friendly file work.

## A Cleaner Interface, Not More Clutter

The most visible update is the UI overhaul.

The editor chrome, document tabs, project sidebar, table of contents, minimap, and Markdown preview have all been tightened. Corners are more consistent. Divider lines are quieter. The translucent modes are less washed out. Sidebar rows on iPhone and iPad are denser, and document tabs feel more intentional.

That may sound cosmetic, but in an editor it matters. Small visual conflicts become tiring when you stare at them all day. The recent work was about removing that friction: fewer unnecessary lines, better spacing, clearer active states, and cleaner transitions between the editor, preview, minimap, and sidebars.

## Navigation for Large Files

The new minimap is one of the most important additions.

It is not just a decorative strip. It is scroll-synced, wider than the first implementation, and color-coded for different kinds of content: sections, declarations, imports, properties, comments, control flow, and regular code.

That makes it easier to understand the shape of a long file without opening a full project-wide symbol browser. It fits the app’s philosophy: give enough context to move quickly, but do not turn the editor into a heavy IDE.

## Markdown Got More Practical

Markdown work has also improved. The preview has cleaner rounded chrome, additional theme refinements, better export behavior, and smoother transitions alongside document tabs.

This matters because Markdown is one of the places where lightweight editors often split into two categories:

- writing apps with beautiful preview but weak code support
- code editors with syntax highlighting but limited Markdown comfort

Neon Vision Editor is trying to sit between those worlds: enough Markdown preview polish for writing, enough code tooling for development notes, scripts, and project files.

## Terminal in the Sidebar

The integrated terminal is intentionally lightweight.

It now lives in the sidebar and keeps its current session while switching between sidebar tabs. The toolbar action also routes to that sidebar terminal instead of opening a separate terminal window.

That keeps the feature small. It is there when you need to run a quick command or inspect a project, but it does not become the center of the app.

## Better Performance Where It Matters

A lot of the recent work was not visually loud, but it matters during real use:

- invisible-character rendering is lighter on iPhone and iPad
- syntax highlighting avoids more repeated work
- large JSON highlighting creates fewer temporary allocations
- Find in Files uses cached line offsets
- folder compare moves heavy file reads and diff work off the main actor
- Markdown export and theme resolution avoid repeated expensive paths
- project tree refresh is more incremental

These changes are the kind of work users only notice when it is missing. The editor should not become unresponsive because invisible characters are enabled, a large file is open, or a sidebar is refreshing.

## How It Compares to CotEditor

CotEditor is one of the clearest references for what a native Mac text editor can be. It is free, open source, fast to launch, and proudly macOS-first. Its official feature set includes syntax highlighting, strong find and replace, an outline menu, split editor support, scripting, encoding tools, and a clean settings experience.

Neon Vision Editor is not trying to replace that identity.

The difference is scope and platform direction. CotEditor is a mature Mac plain-text editor. Neon Vision Editor is a cross-platform Apple editor that is moving into project navigation, sidebar workflows, Markdown preview, mobile editing, Git visibility, a terminal tab, and optional Apple Intelligence integration.

If you want a polished, focused Mac text editor with a long track record, CotEditor remains an obvious choice.

If you want the same lightweight spirit extended across Mac, iPad, and iPhone, with project sidebars, minimap navigation, Markdown preview, and Git-adjacent workflows, Neon Vision Editor is aiming at that space.

## How It Compares to Editorio

Editorio is an interesting new entrant because it is also native, free, and positioned around Markdown plus code editing. Public descriptions highlight live Markdown preview, code syntax highlighting, light/dark themes, tabs, a minimap, and a very lean AppKit approach.

That overlaps with some of the same pain points: people want fast native editors that do not require opening a full IDE just to inspect Markdown or code.

The difference is that Neon Vision Editor is leaning into a broader Apple-platform workflow:

- macOS, iPadOS, and iOS support
- project sidebar and table of contents sidebar
- sidebar terminal
- Git-oriented panels
- native diff workflows
- optional command-line helper flow
- Markdown preview/export refinements
- extensive mobile toolbar and keyboard work
- sandbox-aware update and file-access behavior
- Apple Foundation Models integration where available

Editorio looks like a strong new Markdown/code editor for Mac users who want a very small native tool. Neon Vision Editor is becoming more of a lightweight editor workspace across Apple devices.

That distinction matters. There is room for both approaches.

## The Design Principle

The guiding constraint is simple:

Add workflow power, but do not add IDE weight.

That means features need to stay small and direct. A minimap should help you navigate. A terminal should stay tucked into the sidebar. Git panels should make common inspection easier. Markdown preview should be useful without turning the app into a publishing suite.

The recent work has been about finding that balance.

## What Comes Next

The app is now in a better place for everyday use:

- cleaner visual structure
- faster large-file behavior
- better mobile ergonomics
- stronger Markdown support
- more useful project navigation
- a persistent terminal workflow
- more reliable release and documentation automation

The next challenge is keeping that direction disciplined. Native editors become valuable because they stay fast, predictable, and respectful of the system.

That is the bar for Neon Vision Editor: keep the speed, keep the native feel, and add only the features that make editing easier.

## Links

- Neon Vision Editor on GitHub: https://github.com/h3pdesign/Neon-Vision-Editor
- Neon Vision Editor on the App Store: https://apps.apple.com/de/app/neon-vision-editor/id6758950965
- CotEditor: https://coteditor.com/
- Editorio on the App Store: https://apps.apple.com/de/app/editorio/id6759334075?mt=12
- Public Editorio discussion referenced for feature positioning: https://www.reddit.com/r/macapps/comments/1tgpbb7/mac_editorio_native_macos_markdown_code_editor/
