import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class ProjectSidebarExpansionStoreTests: XCTestCase {
    func testDecodesExpansionPerProjectRoot() {
        let stored = ProjectSidebarExpansionStore.decode(#"{"/p/a":["/p/a/src","/p/a/src/ui"],"/p/b":[]}"#)
        XCTAssertEqual(stored["/p/a"], ["/p/a/src", "/p/a/src/ui"])
        XCTAssertEqual(stored["/p/b"], [])
    }

    func testEmptyOrMalformedValueDecodesToNoExpansion() {
        XCTAssertTrue(ProjectSidebarExpansionStore.decode("").isEmpty)
        XCTAssertTrue(ProjectSidebarExpansionStore.decode("not json").isEmpty)
        XCTAssertTrue(ProjectSidebarExpansionStore.decode(#"{"/p":"x"}"#).isEmpty)
    }

#if os(macOS)
    /// Native Mac tabs are separate windows; a file opened from the sidebar
    /// lands in a new tab, which must read the same expansion state.
    func testMacUsesAppWideStorageKey() {
        XCTAssertEqual(ProjectSidebarExpansionStore.sharedStorageKey, "ProjectSidebarExpandedDirectories.shared.v1")
    }
#endif
}
