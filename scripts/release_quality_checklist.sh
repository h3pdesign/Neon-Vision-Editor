#!/bin/sh
set -eu

tag="${1:-v0.7.0}"

echo "Release quality checklist for ${tag}"
echo
echo "[ ] scripts/ci/build_platform_matrix.sh"
echo "[ ] scripts/ci/release_preflight.sh ${tag}"
echo "[ ] scripts/ci/xcode_cloud_release_preflight.sh"
echo "[ ] scripts/benchmark_large_file.sh 100000"
echo "[ ] scripts/draft_issue_changelog.sh ${tag}"
echo "[ ] Verify iCloud Appearance & Theme Sync on two signed-in devices"
echo "[ ] Verify scripts/nve --help, scripts/nve --wait, scripts/nve --new-window"
echo "[ ] Verify scripts/nve uses /usr/bin/open and does not request Full Disk Access, Accessibility, admin rights, or direct file-content access"
echo "[ ] Confirm App Store Connect metadata does not claim an embedded command-line helper unless one is actually bundled"
echo "[ ] Confirm Xcode Cloud uses scheme 'Neon Vision Editor AppStore' with the latest public GM Xcode, not Xcode beta"
echo "[ ] Verify Terminal sidebar keeps output while switching tabs"
echo "[ ] Verify Project sidebar ignores .git, .build, node_modules, and DerivedData by default"
echo "[ ] Prepare App Store Connect update text from CHANGELOG.md"
